#!/bin/bash

CMD=$1
JIRA_SITE="${SDM_JIRA_SITE:-}"

function error() {
    echo -e "\033[0;31mERROR: $1\033[0m"
}

function ok() {
    echo -e "\033[0;32m$1\033[0m"
}

function launchClient() {
    ok "Launching your client to open ${1}"
    open "${SDM_CLIENT_SCHEME:-mysql}://${1}"
}

function disconnect() {
    # disconnect() will disconnect you for any active connections and shutdown
    # any active listening port forwards.
    ACTIVE_LISTENS=($(ps -A | grep "[s]dm listen" | awk '{print $1}'))

    for ACTIVE_LISTEN in "${ACTIVE_LISTENS[@]}"
    do
        ok "Shutting down active listen pid ${ACTIVE_LISTEN}"
        kill -9 "${ACTIVE_LISTEN}"
    done

    sdm disconnect -all >> /dev/null 2>&1
}

function connect() {
    CONNECTION="${1}"
    sdm listen "${CONNECTION}" >/dev/null 2>&1 &
    sdm connect "${CONNECTION}" >/dev/null 2>&1

    sleep 1
}

function getConnected() {
    sdm status | jc --asciitable | jq -r '.[] | select( .status == "connected")' | jq -r '.address'
}

function getApprovedResource() {
    sdm status | jc --asciitable | jq -r ".[] | select( .datasource == \"${1}\")" | jq -r '.address'
}

function jiraProjects() {
    local START_AT=0
    local PAGE
    local MORE=true

    while [[ $MORE == true ]]
    do
        PAGE=$(curl -s -u "${JIRA_API_USERNAME}:${JIRA_API_TOKEN}" -H 'Accept: application/json' \
            "https://${JIRA_SITE}/rest/api/3/project/search?startAt=${START_AT}&maxResults=50")
        echo "${PAGE}" | jq -r '.values[]? | [.name, .key] | @tsv'
        MORE=$(echo "${PAGE}" | jq -r '.isLast == false')
        START_AT=$(( START_AT + 50 ))
    done
}

function jiraAccountId() {
    curl -s -G -u "${JIRA_API_USERNAME}:${JIRA_API_TOKEN}" -H 'Accept: application/json' \
        "https://${JIRA_SITE}/rest/api/3/user/search" --data-urlencode "query=${JIRA_API_USERNAME}" \
        | jq -r --arg email "${JIRA_API_USERNAME}" '[.[]? | select((.emailAddress // "" | ascii_downcase) == ($email | ascii_downcase))] | .[0].accountId // empty'
}

function createJiraTicket() {
    jq -n --arg project "${1}" --arg summary "${2}" --arg description "${3}" --arg team "${4}" --arg assignee "${5}" \
        '{fields: ({project: {key: $project}, summary: $summary, issuetype: {name: "Task"}, assignee: {accountId: $assignee}, description: {type: "doc", version: 1, content: [{type: "paragraph", content: [{type: "text", text: $description}]}]}} + (if $team == "" then {} else {customfield_13100: $team} end))}' \
    | curl -s -X POST -u "${JIRA_API_USERNAME}:${JIRA_API_TOKEN}" \
        -H 'Accept: application/json' -H 'Content-Type: application/json' \
        --data @- "https://${JIRA_SITE}/rest/api/3/issue" \
    | jq -r '.key // empty'
}

function jiraSupportsTeam() {
    local TASK_TYPE_ID
    TASK_TYPE_ID=$(curl -s -u "${JIRA_API_USERNAME}:${JIRA_API_TOKEN}" -H 'Accept: application/json' \
        "https://${JIRA_SITE}/rest/api/3/issue/createmeta/${1}/issuetypes" \
        | jq -r '.issueTypes[]? | select(.name == "Task") | .id' | head -1)
    curl -s -u "${JIRA_API_USERNAME}:${JIRA_API_TOKEN}" -H 'Accept: application/json' \
        "https://${JIRA_SITE}/rest/api/3/issue/createmeta/${1}/issuetypes/${TASK_TYPE_ID}?maxResults=200" \
        | jq -r '[.fields[]? | select(.fieldId == "customfield_13100")] | length > 0'
}

function connectAndLaunch() {
    connect "${1}"
    CONNECTED=$(getConnected)

    if [[ $CONNECTED == "" ]];
    then
        error "We could not connect you or you made an invalid choice."
        error "exiting..."
        exit 0
    fi

    # Launch
    launchClient "${CONNECTED}"
}

# Check for dependencies
declare -a DEPENDENCIES=("jq" "jc" "sdm" "awk" "dialog")

MISSING_DEPS=false
for DEPENDENCY in "${DEPENDENCIES[@]}"
do
    HAS_DEP=$(which "${DEPENDENCY}")

    if [[ $HAS_DEP == "" ]];
    then
        MISSING_DEPS=true
        error "You are missing the ${DEPENDENCY}."
        error "brew install ${DEPENDENCY}"
    fi
done

if [[ $MISSING_DEPS = true ]];
then
    error "exiting..."
    exit 1
fi

# Is the user logged in?
# The 'no' is caught from stderr oddly.
SDM_STATUS_RESPONSE=$(sdm status 2>&1 >/dev/null)

if [[ $SDM_STATUS_RESPONSE == 'You are not authenticated. Please login again.' ]];
then
    if [[ $SDM_EMAIL == "" ]];
    then
        error "You are not logged in and you have no SDM_EMAIL environmental variable set."
        error "Add SDM_EMAIL to your ~/.*rc file."
        error "exiting..."
        exit 1
    fi

    sdm login
fi

disconnect

if [[ $CMD == "" || $CMD == "connect" ]];
then
    # Always disconnect to remove the possibility of accidentally connecting to the
    # wrong resource. Should in theory be impossible as its based on port
    # assigning.
    ok "Select from the list below to connect or CTRL+C to exit"

    declare -a CONNECTIONS=$(sdm status | jc --asciitable | jq -r '.[].datasource')

    select CONNECTION in $CONNECTIONS
    do
        connect "${CONNECTION}"
        CONNECTED=$(getConnected)
        break
    done

    if [[ $CONNECTED == "" ]];
    then
        error "We could not connect you or you made an invalid choice."
        error "exiting..."
        exit 0
    fi

    # Launch
    launchClient "${CONNECTED}"
fi

if [[ $CMD == "request" ]];
then
    if [ ! -f ~/.sdmr-cli-config ]; then
        error "~/.sdmr-cli-config not found"
        error ""
        ok "Do you want us to create a basic file for you to edit? (N/y)"

        read CREATE_FILE

        if [[ $CREATE_FILE == "y" ]];
        then
            echo 'declare -a SDM_RESOURCES=(' >> ~/.sdmr-cli-config
            echo '"Easy to read name 1" "id-1-from-strongdm"' >> ~/.sdmr-cli-config
            echo '"Easy to read name 2" "id-2-from-strongdm"' >> ~/.sdmr-cli-config
            echo ')' >> ~/.sdmr-cli-config

            ok "We have created the file, this process will now exit so you can edit the file."
            ok "exiting..."
            exit 0
        fi

        ok "We did not create the file for you, to use the request process this"
        ok "file needs to exist and be populated with your commonly used clusters"
        ok "exiting..."
        exit 0
    fi

    source ~/.sdmr-cli-config

    RESOURCE_CHOICE=$(dialog --clear \
            --title "Choose a resource to make a request" \
            --menu "Choose one of the following resources:" \
            400 200 4 \
            "${SDM_RESOURCES[@]}" 2>&1 >/dev/tty)


    RESOURCE_CHOICE_ID=""
    for RESOURCE_INDEX in "${!SDM_RESOURCES[@]}"
    do
        if [[ ${SDM_RESOURCES[$RESOURCE_INDEX]} == $RESOURCE_CHOICE ]];
        then
            RESOURCE_CHOICE_ID="${SDM_RESOURCES[$RESOURCE_INDEX+1]}"
            break
        fi
    done

    clear

    if [[ $RESOURCE_CHOICE_ID == "" ]];
    then
        error "You cancelled or made an invalid selection"
        error "exiting..."
        exit 1
    fi

    TICKET_CHOICE=$(dialog --clear \
            --title "Jira ticket" \
            --menu "Is this access for an existing ticket or a new one?" \
            400 200 2 \
            "Existing ticket" "Use a ticket you already have" \
            "New ticket" "Create a new Jira ticket" 2>&1 >/dev/tty)

    clear

    if [[ $TICKET_CHOICE == "" ]];
    then
        error "You cancelled or made an invalid selection"
        error "exiting..."
        exit 1
    fi

    if [[ $TICKET_CHOICE == "New ticket" ]];
    then
        if [[ $JIRA_API_USERNAME == "" || $JIRA_API_TOKEN == "" ]];
        then
            error "You need JIRA_API_USERNAME and JIRA_API_TOKEN set to create a ticket."
            error "exiting..."
            exit 1
        fi

        if [[ $JIRA_SITE == "" ]];
        then
            error "You need SDM_JIRA_SITE set to your Jira site, e.g. your-org.atlassian.net."
            error "exiting..."
            exit 1
        fi

        if [[ ${#SDM_JIRA_PROJECTS[@]} -gt 0 ]];
        then
            PROJECT_MENU=("${SDM_JIRA_PROJECTS[@]}")
        else
            PROJECT_MENU=()
            while IFS=$'\t' read -r PROJECT_NAME PROJECT_KEY
            do
                PROJECT_MENU+=("${PROJECT_NAME}" "${PROJECT_KEY}")
            done < <(jiraProjects)
        fi

        if [[ ${#PROJECT_MENU[@]} -eq 0 ]];
        then
            error "There are no Jira projects to choose from."
            error "Check ~/.sdmr-cli-config, or your JIRA_API_USERNAME, JIRA_API_TOKEN and SDM_JIRA_SITE."
            error "exiting..."
            exit 1
        fi

        PROJECT_CHOICE=$(dialog --clear \
                --title "Choose a Jira project" \
                --menu "Choose the project for the new ticket:" \
                400 200 4 \
                "${PROJECT_MENU[@]}" 2>&1 >/dev/tty)

        clear

        if [[ $PROJECT_CHOICE == "" ]];
        then
            error "You cancelled or made an invalid selection"
            error "exiting..."
            exit 1
        fi

        PROJECT_KEY=""
        for PROJECT_INDEX in "${!PROJECT_MENU[@]}"
        do
            if [[ ${PROJECT_MENU[$PROJECT_INDEX]} == "${PROJECT_CHOICE}" ]];
            then
                PROJECT_KEY="${PROJECT_MENU[$PROJECT_INDEX+1]}"
                break
            fi
        done

        TEAM_ID=""

        if [[ ${#SDM_JIRA_TEAMS[@]} -gt 0 && $(jiraSupportsTeam "${PROJECT_KEY}") == "true" ]];
        then
            TEAM_CHOICE=$(dialog --clear \
                    --title "Choose a team" \
                    --menu "Choose the team for the new ticket:" \
                    400 200 4 \
                    "${SDM_JIRA_TEAMS[@]}" 2>&1 >/dev/tty)

            clear

            if [[ $TEAM_CHOICE == "" ]];
            then
                error "You cancelled or made an invalid selection"
                error "exiting..."
                exit 1
            fi

            for TEAM_INDEX in "${!SDM_JIRA_TEAMS[@]}"
            do
                if [[ ${SDM_JIRA_TEAMS[$TEAM_INDEX]} == "${TEAM_CHOICE}" ]];
                then
                    TEAM_ID="${SDM_JIRA_TEAMS[$TEAM_INDEX+1]}"
                    break
                fi
            done
        fi

        ok "Please enter a reason for this access."
        read -r TICKET_DESCRIPTION

        if [[ $TICKET_DESCRIPTION == "" ]];
        then
            error "A reason is required."
            error "exiting..."
            exit 1
        fi
    else
        ok "Please enter a reason for this access."
        read REASON
    fi

    declare -a TIMES=(
        "15 Minutes" "15m"
        "30 Minutes" "30m"
        "1 Hour" "1h"
        "2 Hours" "2h"
        "4 Hours" "4h")

    TIME_CHOICE=$(dialog --clear \
            --title "Choose a length of time" \
            --menu "Choose a length of time for this request:" \
            400 200 4 \
            "${TIMES[@]}" 2>&1 >/dev/tty)


    TIME_CHOICE_ID=""
    for TIME_INDEX in "${!TIMES[@]}"
    do
        if [[ ${TIMES[$TIME_INDEX]} == $TIME_CHOICE ]];
        then
            TIME_CHOICE_ID="${TIMES[$TIME_INDEX+1]}"
            break
        fi
    done

    clear

    if [[ $TIME_CHOICE_ID == "" ]];
    then
        error "You cancelled or made an invalid selection"
        error "exiting..."
        exit 1
    fi

    if [[ $TICKET_CHOICE == "New ticket" ]];
    then
        ASSIGNEE_ID=$(jiraAccountId)

        if [[ $ASSIGNEE_ID == "" ]];
        then
            error "We could not find a Jira account for ${JIRA_API_USERNAME}."
            error "exiting..."
            exit 1
        fi

        NEW_TICKET=$(createJiraTicket "${PROJECT_KEY}" "${SDM_EMAIL} needs access to ${RESOURCE_CHOICE} for ${TIME_CHOICE}" "${TICKET_DESCRIPTION}" "${TEAM_ID}" "${ASSIGNEE_ID}")

        if [[ $NEW_TICKET == "" ]];
        then
            error "We could not create the Jira ticket."
            error "exiting..."
            exit 1
        fi

        ok "Created ${NEW_TICKET}: https://${JIRA_SITE}/browse/${NEW_TICKET}"
        open "https://${JIRA_SITE}/browse/${NEW_TICKET}"
        REASON="${NEW_TICKET} ${TICKET_DESCRIPTION}"
    fi

    if [[ $RESOURCE_CHOICE_ID != "" ]];
    then
        ACCESS_REQUEST_ID=$(sdm access to "${RESOURCE_CHOICE_ID}" \
            --timeout "30s" \
            --reason "${REASON} - SDMR-CLI" \
            --duration "${TIME_CHOICE_ID}")

        ok "I will now wait for that approval for a max of 15 seconds in case"
        ok "the request is auto approved..."

        x=1
        while [ $x -le 15 ]
        do
            ok "Checking for approval to ${RESOURCE_CHOICE_ID}"
            IS_APPROVED=$(getApprovedResource "${RESOURCE_CHOICE_ID}")

            if [[ $IS_APPROVED != "" ]];
            then
                connectAndLaunch "${RESOURCE_CHOICE_ID}"

                exit 0
            fi
            sleep 1

            x=$(( $x + 1 ))
        done

        ok "Your request was not auto approved."
        ok
        ok "Your access request has been sent, you will receive a notification"
        ok "soon when it is approved. Re-running 'sdmr-cli connect' command will show"
        ok "that connection once it has been approved."
    fi
fi