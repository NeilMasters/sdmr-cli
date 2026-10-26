# sdmr-cli
`sdmr-cli` is a small sidecar script to supplement sdm cli
functionality and automate requests, connections and client opening for
database type resources.

> This script is prone to rapid change and improvement. It has been written 
> with a single persons use case in mind and will likely expand to cover more
> use cases in due course as well as just making it work on various 
> environments.

1. [Features](#features)
2. [Who would you use this?](#who-would-you-use-this)
3. [Usage](#usage)
   1. [Making a request, connecting and opening your client](#1-making-a-request-connecting-and-opening-your-client)
   2. [Connecting to an already approved request and opening your client](#2-connecting-to-an-already-approved-request-and-opening-your-client)
   3. [Creating a new Jira ticket](#creating-a-new-jira-ticket)
4. [Installation](#installation)
   1. [Install and symlink](#install-and-symlink)
   2. [Manual step by step](#manual-step-by-step)
      1. [Create your config file](#1-create-your-config-file)
      2. [Add your strongdm email as an environment variable](#2-add-your-strongdm-email-as-an-environment-variable)
      3. [Install any dependencies](#3-install-any-dependencies)

## Features
1. Automatically sets up any dependencies or tells you what to do.
2. Automates request management
3. Simplifies connection handling
4. Auto opens your client with the connection details
5. Creates a Jira ticket for a new access request, or uses an existing one

There is much more this can potentially do and your pull requests are
appreciated. It is very much so a tool that I wrote to satisfy my own
use cases, but I hope it can help others too.

## Who would you use this?
StrongDM has a desktop client that allows users to connect to resources
managed by StrongDM. However, the process of requesting access and
connecting to these resources can be cumbersome and time-consuming
due to a lack of support for specific features.

This is especially true for users who frequently need to request access
to a lot of different resources.

This simple script aims to shortcut multiple parts of the process by
automating the entire journey from access to request to connection and
then opening your client.

1. Make a request; selecting the resource, the time duration and reason.
2. App will wait for approval (upto 15 seconds)
3. Open your client with the connection details pre-populated

You do not need to access the StrongDM web console or even open the
StrongDM desktop client.

> If you have perma-access to all your resources or do not need to make
> requests very often then this script may not be for you as it is unlikely
> to save you much time.

## Usage
### Making a request, connecting and opening your client
This command will show multiple dialog screens to help you make your choice.
Upon approval it will open your client automatically. If approval is not
automatic or the approvers are slow it will display a message tell you to run
again with `sdmr-cli connect`.

```bash
sdmr-cli request
```

### Connecting to an already approved request and opening your client
This command will connect to any already approved requests and open your
client automatically.

```bash
sdmr-cli connect
```

The client opened is chosen by the `SDM_CLIENT_SCHEME` environment variable, which
defaults to `mysql`. For example, set `SDM_CLIENT_SCHEME=postgresql` to open
`postgresql://` links instead.

### Creating a new Jira ticket
When making a request you choose either an existing ticket or a new one. For an
existing ticket you enter the ticket number and a reason, as before. For a new
ticket you choose a Jira project and enter a reason; the script creates a Task
in that project with your reason as the description, assigned to the Jira account
matching `JIRA_API_USERNAME`. The title is generated as
"<SDM_EMAIL> needs access to <resource> for <time>", and the new ticket key is used
as the reason for the request.

This needs your Jira credentials in your shell profile:

```bash
export JIRA_API_USERNAME="your.email@org.tld"
export JIRA_API_TOKEN="your-jira-api-token"
export SDM_JIRA_SITE="your-org.atlassian.net"
```

Create an API token at https://id.atlassian.com/manage-profile/security/api-tokens.
`SDM_JIRA_SITE` is your Jira site, without `https://`.

By default the project menu lists every project in Jira. To choose from a curated
list instead, add `SDM_JIRA_PROJECTS` to `~/.sdmr-cli-config`, with a name and project
key for each entry:

```bash
declare -a SDM_JIRA_PROJECTS=(
"Easy to read name 1" "PROJ1"
"Easy to read name 2" "PROJ2"
)
```

The same file holds `SDM_JIRA_TEAMS`, with a team name and its Jira team ID for
each entry. After you choose a project, the script shows the team menu only if that
project's Task create screen includes the Team field; otherwise the step is skipped.
The chosen team is set on the new ticket.

## Installation
The script itself will do most of this setup for you. These steps are being
documented here for those who wish a more manual and involved setup.

### Install and symlink
As this is just bash scripts, you can use it in a variety of ways; if you
want to deviate from the instructions below absolutely do so.

```bash
git clone git@github.com:NeilMasters/sdmr-cli.git
cd sdmr-cli
chmod +x sdmr-cli.sh
sudo ln -s $(pwd)/sdmr-cli.sh /usr/local/bin/sdmr-cli
```

### Manual step by step

#### 1. Create your config file
Because not every environment allows API access this script reads resources
from a ~/.sdmr-cli-config file, which also holds the optional Jira projects and teams.

The application on first run will create a template file for you to manually
edit. You can also create this file manually.

```bash
echo 'declare -a SDM_RESOURCES=(' >> ~/.sdmr-cli-config
echo '"Easy to read name 1" "id-1-from-strongdm"' >> ~/.sdmr-cli-config
echo ')' >> ~/.sdmr-cli-config
```

After this simply edit the file and add your own resources. The simplest method
of obtaining a resources list is by copying and pasting the resource ids
from the [StrongDM catalog](https://app.uk.strongdm.com/app/requests/catalog).

**Why not use API access instead?**
1. Not every environment allows API access. Some organizations
have strict security policies that prevent the use of API keys or tokens,
or they may have compliance requirements that mandate manual access
controls.
2. Depending on your organisations size and complexity this can potentially lead
to unwieldy lists. This manual method allows you to curate your own list of
resources that you commonly need access to.

### 2. Add your strongdm email as an environment variable
The script needs to know your strongdm email address to be able to
make requests on your behalf and trigger authentication. You can set this in
your shell profile; typically this is ~/.bashrc or ~/.zshrc.

```bash
export SDM_EMAIL="your.email@org.tld"
```

> The script itself does not ever use or access the contents of  SDM_EMAIL 
> value. It is used by the sdm cli directly. We reference the variable within 
> the script purely as a helper for setup.

#### 3. Install any dependencies
Fortunately if you are wanting to utilize this script then you will
already have the sdm desktop app/cli. There is a very high probability
that you have the other dependencies too.

The script itself will check for these dependencies and if you are missing
any of them will prompt you and then exit.

1. sdm cli - https://strongdm.com/docs/quickstart/install-cli
2. jq
3. jc
4. awk
5. dialog

I have included some quick one-liners below if you need the full list of
dependencies.

```bash
# Debian/Ubuntu
apt install -y jq jc awk dialog
# MacOS (with homebrew)
brew install jq jc awk dialog
```