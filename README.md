# Repo Analytics

Originally created by @admiralawkbar.

This script is used to gather information about all or a subset of repositories on a **GitHub Enterprise** system.  
Once the script has ran, it will generate the file: `repo-analytics.csv` with all results.  
The results file can then be used to help triage information about your current system and usage.  

**Note:** The script utilizes the **GitHub** Graphql API to limit api calls, but for larger systems you could encounter the upper limit.

## How to run

To run the script effectively you will need to have the following in order:

- The script should be ran from a `MacOS` or `Linux` based machine
  - Running from the **GHE** instance is a preferred location
- The user will need to provide the script with the following information:
  - **GitHub.com** Organization **OR** the *URL* to the **GHE** instance
  - **GitHub** Personal Access Token for query of API's
- The User will need to be an **admin** of all Organizations that are queried
  - If **GitHub.com**, this will only require a single Organization to be admin over
  - If **GHE**, this could lead to an interesting amount of ownership if you have many Organizations
    - Please see Section on `Running against many Organizations` before running the script
- Once all criteria is met, you should be good to run the script to completion
- Copy the script `repo-analytics.sh` to the local machine
- Set to execute
  - `chmod +x repo-analytics.sh`
- Execute the script and follow the additional prompts
  - `./repo-analytics.sh`
- **Note:** *you can pass the script a list of newline separated **GitHub** Organizations to query a smaller subset if needed*
- Save the results file and enjoy the fruits of its bounty...

## Results

The results will be a generated file named: `repo-analytics.csv`.
The file will have the format as below:

```csv
ORG_NAME,REPO_NAME,CREATED_AT,PUSHED_AT,ACTIVE_IN_LAST_6_MONTHS,OVER_1YR_NO_ACTIVITY,OVER_2YR_NO_ACTIVITY,OVER_5YR_NO_ACTIVITY,OVER_7YR_NO_ACTIVITY
demo-org,Demo-Hubot,2019-07-19T13:06:35Z,2019-07-19T13:40:03Z,X,,,,
demo-org,Ruby-Books,2018-07-19T13:06:48Z,2018-07-19T13:20:59Z,,X,,,
demo-org,Demo-Admin-Toolbox,2017-07-19T13:06:51Z,2017-07-19T13:06:55Z,,,X,,
demo-org,Demo-Tiered-App,2014-07-19T13:06:56Z,2014-07-19T13:07:01Z,,X,X,X,
demo-org,test-Webhook,2011-07-19T14:10:58Z,2011-07-19T14:22:07Z,,X,X,X,X
additional-org,additional-Hubot,2019-07-19T13:06:35Z,2019-07-19T13:40:03Z,X,,,,
additional-org,Ruby-Books,2018-07-19T13:06:48Z,2018-07-19T13:20:59Z,,X,,,
additional-org,additional-Admin-Toolbox,2017-07-19T13:06:51Z,2017-07-19T13:06:55Z,,,X,,
additional-org,additional-Tiered-App,2014-07-19T13:06:56Z,2014-07-19T13:07:01Z,,X,X,X,
additional-org,test-Webhook,2011-07-19T14:10:58Z,2011-07-19T14:22:07Z,,X,X,X,X
...
...
...
```

This data can easily be parsed and formatted using pivot tables to help showcase:

- **Active** repositories in your ecosystem
- Repositories that have **no activity** in `X` amount of years
  - This can be used for your internal audit and cleanup of the system

--------------------------------------------------------------------------------

### Running against many Organizations

If you have many Organizations in your **GHE** instance (more than a handful), you may want to consider utilizing an automation account.  
Again, the account will need to be an **admin** of **all** Organizations in your system to be able to grab all information. In addition, adding yourself to all Organizations could lead to the spamming of your account, and interesting drop downs when trying to find information. It is for this case we suggest building an *admin automation account* to perform such actions.  
To create an Additional Admin type account:

- Navigate to your **GHE** admin web UI console
  - `https://your-ghe-url:8443`
- Depending on your Authentication model, you may need to enable `Allow creation of accounts with built-in authentication (for users not in LDAP)`
- Create a new account and add the account to the **GHE** instance
  - Save the `username` and `password` for later use
- Navigate to the **GHE** ssh console
  - `ssh -p 122 admin@your-ghe-primary`
- Run the command line option to make that account an admin of all Organizations
  - `ghe-org-admin-promote -u YourNewAdminAccountName`
  - This command will add that account name as an admin to all Organizations in your ecosystem
  - *Note: this could take several moments...*
- Log into the Web UI of your system as the newly created Admin account and create a Personal Access Token
  - [Create Token](https://help.github.com/en/articles/creating-a-personal-access-token-for-the-command-line)
  - Give the account `repo` and `admin:org read:org` so that it can query the information
  - Save the generated token to a secure location
- You can now use this token for performing the proper authentication for the `repo-analytics.sh` script

#### Removing Admin User from all Organizations

If you added an account to all to all GitHub Organizations and wish to remove the user, you will need to run the following commands:

- Navigate to the **GHE** ssh console
  - `ssh -p 122 admin@your-ghe-primary`
- Create a file to hold the ruby script
  - `vi /home/admin/remove_user.rb`
- Add the following contents to the file: (NOTE: change `user` to the user account name)

```Ruby
Organization.find_each do |o|
  if o.login == "github-enterprise"
    next
  end
    o.remove_member(User.find_by_login("user"))
    puts "Removed from Organization: " + o.login
  end
```

- Save the file
- Run the command to remove that account from all Organizations
  - `sudo github-env bin/runner -e production /home/admin/remove_user.rb`
- The user account will now have been removed from **ALL** Organizations in the system
