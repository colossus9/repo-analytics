#!/bin/bash
################################################################################
################################################################################
####### Repo analytics @AdmiralAwkbar ##########################################
################################################################################
################################################################################

# LEGEND:
# This script will use pagination and the github API to collect a list
# of all repos for all organizations.
# It will then gather information about them and build a csv.
#
# PREREQS:
# You need to have the following to run this script successfully:
# - GitHub Personal Access Token with access to the Organization
# - jq installed on the machine running the query
#
# HOW To Run:
# - Copy file to GHE Primary instance or your local workstation
# - chmod +x file.sh
# - ./file.sh
# - The script will prompt for Url, Optional Org name, and a personal access token to query
#
# ASSUMPTIONS:
# - The personal access token used has repo and org access
# - The owner of the personal access token has access to all Organizations if GHE
#
###########
# GLOBALS #
###########
OUTPUT_FILE='repo-analytics.csv'  # File to store output of data
GITHUB_URL=''                     # GitHub URL
GITHUB_API_URL=''                 # API v3 url
GRAPHQL_URL=''                    # Graphql API URL
ORG_NAME=''                       # Name of the GitHub.com Organization to query
ORG_ARRAY=()                      # Array of all GitHub Organizations
USER_LOGIN=''                     # User Login info
PAGE_SIZE='100'                   # Size od page to return from API
END_CURSOR_REPOS='null'           # Default value for the end cursor on API for repos
END_CURSOR_ORGS='null'            # Default value for the end cursor on API for orgs
DATE_CMD=''                       # Filled in with OS |linux=date macOS=gdate
GITHUB_PAT=''                     # Personal access token to auth
GHE_URL=""                        # URL for GHE
DEBUG=0                           # 0=Debug OFF | 1=Debug ON

################################################################################
############################ FUNCTIONS #########################################
################################################################################
################################################################################
#### Function Header ###########################################################
Header()
{
  echo ""
  echo "######################################################"
  echo "######################################################"
  echo "############### GitHub Repo Analytics ################"
  echo "######################################################"
  echo "######################################################"
  echo ""
  echo "This script will use the GitHub API to gather information about"
  echo "all GitHub repositories."
  echo "It will generate:[$OUTPUT_FILE] with all output when completed."
  echo ""
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo "!!! NOTE: You will need to be an admin of all Organizations !!!"
  echo "!!! to query the full data set. Please view documentation.  !!!"
  echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
  echo ""

}
################################################################################
#### Function Footer ###########################################################
Footer()
{
  #######################
  # Remove the raw file #
  #######################
  # only remove file when NOT in debug
  if [ $DEBUG -eq 0 ]; then
    RM_FILE_CMD=$(rm -f "$RAW_FILE")

    #######################
    # Load the error code #
    #######################
    ERROR_CODE=$?

    ##############################
    # Check the shell for errors #
    ##############################
    if [ $ERROR_CODE -ne 0 ]; then
      echo "ERROR! Failed to remove file!"
      echo "ERROR:[$RM_FILE_CMD]"
      exit 1
    fi
  fi

  #######################################
  # Basic footer information and totals #
  #######################################
  echo ""
  echo "######################################################"
  echo "The script has completed"
  echo "Please view:[$OUTPUT_FILE] for data"
  echo "######################################################"
  echo ""
  echo ""
}
################################################################################
#### Function GetGitHubInfo ####################################################
GetGitHubInfo()
{
  ###################################################
  # See if were going to GitHub.com or GHE instance #
  ###################################################
  echo ""
  echo "------------------------------------------------------"
  echo "Is the Organization on GitHub.com?"
  echo "(y)es (n)o, followed by [ENTER]:"
  ########################
  # Read input from user #
  ########################
  read -r GITHUB

  #######################
  # Validate user input #
  #######################
  if [[ "$GITHUB" == "yes" ]] || [[ "$GITHUB" == "y" ]]; then
    ##############
    # GITHUB.COM #
    ##############
    ################
    # Set the URLS #
    ################
    GITHUB_URL='https://github.com'
    GITHUB_API_URL='https://api.github.com'
    GRAPHQL_URL="$GITHUB_API_URL/graphql"

    #########################
    # Get the Org name info #
    #########################
    echo ""
    echo "------------------------------------------------------"
    echo "Please give the name of the GitHub.com Organization"
    echo "to query the repositories, followed by [ENTER]:"

    ########################
    # Read input from user #
    ########################
    read -r ORG_NAME

    ############################################
    # Clean any whitespace that may be entered #
    ############################################
    ORG_NAME_NO_WHITESPACE="$(echo -e "${ORG_NAME}" | tr -d '[:space:]')"
    ORG_NAME=$ORG_NAME_NO_WHITESPACE
  else
    #####################
    # GITHUB ENTERPRISE #
    #####################
    echo ""
    echo "------------------------------------------------------"
    echo "Please give the URL to the GitHub Enterprise instance you would like to query"
    echo "in the format: https://ghe-url.com"
    echo "followed by [ENTER]:"
    ########################
    # Read input from user #
    ########################
    read -r GHE_URL

    ############################################
    # Clean any whitespace that may be entered #
    ############################################
    GHE_URL_NO_WHITESPACE="$(echo -e "${GHE_URL}" | tr -d '[:space:]')"
    GHE_URL=$GHE_URL_NO_WHITESPACE

    ####################################
    # Validate we can hit the endpoint #
    ####################################
    CURL_CMD=$(curl -sSk --connect-timeout 3 "$GHE_URL/status")

    #######################
    # Load the error code #
    #######################
    ERROR_CODE=$?

    ###############################
    # Check the return from shell #
    ###############################
    if [ $ERROR_CODE -ne 0 ]; then
      # Bad return
      echo "ERROR! Failed to validate GHE instance:[$GHE_URL]"
      echo "Recieved error:[$CURL_CMD]"
      exit 1
    else
      #####################
      # Check for success #
      #####################
      if [[ $CURL_CMD == *"GitHub lives"* ]]; then
        # Got positive return
        echo "Successfully validated GHE instance:[$GHE_URL]"
      else
        # Got bad return
        echo "ERROR! Failed to validate GHE instance:[$GHE_URL]"
        echo "Recieved error:[$CURL_CMD]"
        exit 1
      fi
    fi

    ################
    # Set the URLS #
    ################
    GITHUB_URL+="$GHE_URL"
    GITHUB_API_URL="$GHE_URL/api/v3"
    GRAPHQL_URL="$GITHUB_URL/api/graphql"

    #######################################
    # Check if all Orgs or a list of Orgs #
    #######################################
    echo ""
    echo "------------------------------------------------------"
    echo "Please provide a file path to a newline separated list of GitHub Organizations, or hit [ENTER]"
    echo "to analyze all GitHub Organizations that you have access to:"
    echo "Example: /tmp/some-file"
    echo ""
    ########################
    # Read input from user #
    ########################
    read -r ORG_LIST

    ############################################
    # Clean any whitespace that may be entered #
    ############################################
    ORG_LIST_NO_WHITESPACE="$(echo -e "${ORG_LIST}" | tr -d '[:space:]')"
    ORG_LIST=$ORG_LIST_NO_WHITESPACE

    ##############################
    # Validate the Org_list file #
    ##############################
    ValidateOrgListFile "$ORG_LIST"
  fi

  ########################################
  # Get the GitHub Personal Access Token #
  ########################################
  echo ""
  echo "------------------------------------------------------"
  echo "Please enter the GitHub Personal Access Token used to gather"
  echo "information from the instance, followed by [ENTER]:"
  echo "(note: your input will NOT be displayed)"
  ########################
  # Read input from user #
  ########################
  read -r -s GITHUB_PAT

  ##########################################
  # Check the length of the PAT for sanity #
  ##########################################
  if [ ${#GITHUB_PAT} -ne 40 ]; then
    echo "GitHub PAT's are 40 characters in length! you gave me ${#GITHUB_PAT} characters!"
    if [ $DEBUG -eq 1 ]; then
      echo "DEBUG --- PAT:[$GITHUB_PAT]"
    fi
    exit 1
  fi

  ################################################################
  # Validate we can hit the endpoint by getting the current user #
  ################################################################
  USER_RESPONSE=$(curl -s -kw '%{http_code}' -X GET \
    --url "${GITHUB_API_URL}/user" \
    --header "authorization: Bearer ${GITHUB_PAT}")

  ###########################
  # Load the data into vars #
  ###########################
  USER_RESPONSE_CODE="${USER_RESPONSE:(-3)}"
  USER_DATA="${USER_RESPONSE::${#USER_RESPONSE}-4}"

  #######################
  # Validate the return #
  #######################
  if [[ "$USER_RESPONSE_CODE" != "200" ]]; then
    echo "Error getting user"
    echo "${USER_DATA}"
  else
    USER_LOGIN=$(echo "${USER_DATA}" | jq -r '.login')
    # Check for success
    if [[ -z $USER_LOGIN ]]; then
      # Got bad return
      echo "ERROR! Failed to validate GHE instance:[$GITHUB_URL]"
      echo "Received error: $USER_DATA"
      exit 1
    fi
  fi

  ###################
  # Prints for Data #
  ###################
  echo ""
  echo "------------------------------------------------------"
  echo "This script will use the GitHub API to connect to:[$GITHUB_URL]"
  echo "and gather information on the Organization(s) of GitHub."
  echo "It will generate a list of all repositories and their data."
  echo "This is usful in helping to size migrations and footprint."
  echo "It will generate:[$OUTPUT_FILE] with all output when completed."
  echo ""
  echo "------------------------------------------------------"
  echo ""
}
################################################################################
#### Function ValidateOutputFile ###############################################
ValidateOutputFile()
{
  ###################################
  # Validate we can write to a file #
  ###################################
  VAL_CONSOLE=$(touch "$OUTPUT_FILE"; rm -f "$OUTPUT_FILE" 2>&1)

  #######################
  # Load the error code #
  #######################
  ERROR_CODE=$?

  ##########################
  # Check the shell return #
  ##########################
  if [ $ERROR_CODE -ne 0 ]; then
    echo "ERROR! Failed to generate output file:[$OUTPUT_FILE]"
    echo "ERROR:[$VAL_CONSOLE]"
    echo "Please validate we have write access in this location"
    echo "Exiting now..."
    exit 1
  fi

  #################################
  # Build the header for the file #
  #################################
  # shellcheck disable=SC2116
  BUILD_HEADER_CMD=$(echo "ORG_NAME,REPO_NAME,CREATED_AT,PUSHED_AT,SIZE_ON_DISK(KB),ACTIVE_IN_LAST_3_MONTHS,ACTIVE_IN_LAST_6_MONTHS,OVER_1YR_NO_ACTIVITY,OVER_2YR_NO_ACTIVITY,OVER_5YR_NO_ACTIVITY,OVER_7YR_NO_ACTIVITY" >> "$OUTPUT_FILE" 2>&1)

  #######################
  # Load the error code #
  #######################
  ERROR_CODE=$?

  ##############################
  # Check the shell for errors #
  ##############################
  if [ $ERROR_CODE -ne 0 ]; then
    #########
    # ERROR #
    #########
    echo "ERROR! Failed to create header on output file!"
    echo "ERROR:[$BUILD_HEADER_CMD]"
    exit 1
  fi
}
################################################################################
#### Function ValidateJQ #######################################################
ValidateJQ()
{
  # Need to validate the machine has jq installed as we use it to do the parsing
  # of all the json returns from GitHub

  ############################
  # See if it is in the path #
  ############################
  CHECK_JQ=$(command -v jq)

  #######################
  # Load the error code #
  #######################
  ERROR_CODE=$?

  ##########################
  # Check the shell return #
  ##########################
  if [ $ERROR_CODE -ne 0 ]; then
    echo "Failed to find jq in the path!"
    echo "ERROR:[$CHECK_JQ]"
    echo "If this is a Mac, run command: brew install jq"
    echo "If this is Debian, run command: sudo apt install jq"
    echo "If this is Centos, run command: yum install jq"
    echo "Once installed, please run this script again."
    exit 1
  fi
}
################################################################################
#### Function GetOrg ###########################################################
GetOrg()
{
  ################################################################
  # LEGEND:
  # ORG_MEMBERSHIP=0 - Not a member of the org, fail to get data
  # ORG_MEMBERSHIP=1 - Admin of org, get all data
  # ORG_MEMBERSHIP=2 - member of org, get some data
  ################################################################
  #############################
  # Only 1 Org to gather data #
  #############################
  echo "Gathering Information for:[$ORG_NAME]"

  ###########################
  # Validate Org membership #
  ###########################
  ORG_MEMBERSHIP=$(ValidateMembership "$ORG_NAME")

  ###########################################
  # Check that we have access to go forward #
  ###########################################
  if [ "$ORG_MEMBERSHIP" -eq 0 ]; then
    # We dont have access
    echo "  - WARN! You do not have access to the Organization:[$ORG_NAME]"
    echo "  - Skipping GitHub Orgainzation..."
  else
    if [ "$ORG_MEMBERSHIP" -eq 2 ]; then
      echo "  - WARN! You only have [member] access of Orgainzation:[$ORG_NAME]"
      echo "  - Data set may not be complete due to access rights..."
    fi
    # We have access
    ################################
    # Call GetRepoData for the Org #
    ################################
    GetRepoData "$ORG_NAME"
  fi
}
################################################################################
#### Function GetAllOrgs #######################################################
GetAllOrgs()
{
  ################################################################
  # LEGEND:
  # ORG_MEMBERSHIP=0 - Not a member of the org, fail to get data
  # ORG_MEMBERSHIP=1 - Admin of org, get all data
  # ORG_MEMBERSHIP=2 - member of org, get some data
  ################################################################

  ##################################
  # Need to build list of all Orgs #
  ##################################
  #####################################
  # Update the end_cursor if not null #
  #####################################
  # Need to quote the string if its not null
  END_CURSOR_ORGS_STRING=$END_CURSOR_ORGS
  if [[ "$END_CURSOR_ORGS" != "null" ]]; then
    END_CURSOR_ORGS_STRING='\"'
    END_CURSOR_ORGS_STRING+="$END_CURSOR_ORGS"
    END_CURSOR_ORGS_STRING+='\"'
  fi

  #####################################################
  # Need to call API to get list of all Organizations #
  #####################################################
  # This call works on GHE after 2.15.x
  DATA_BLOCK=$(curl -s -k -X POST -H "authorization: Bearer $GITHUB_PAT" -H "content-type: application/json" \
  --data '{"query":"query {\n organizations(first: '"$PAGE_SIZE"', after: '"$END_CURSOR_ORGS_STRING"') {\n nodes {\n login\n }\n pageInfo {\n hasNextPage\n endCursor\n }\n}\n}"}' \
  "$GRAPHQL_URL" 2>&1)

  #######################
  # Load the error code #
  #######################
  ERROR_CODE=$?

  ##########################
  # Check the shell return #
  ##########################
  if [ $ERROR_CODE -ne 0 ]; then
    echo "ERROR! Failed to gather data from GitHub!"
    echo "RETURN FROM COMMAND:[$DATA_BLOCK]"
    exit 1
  fi

  #########################
  # DEBUG show data block #
  #########################
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG --- DATA BLOCK:[$DATA_BLOCK]"
  fi

  ##########################
  # Get the Next Page Flag #
  ##########################
  NEXT_PAGE_ORGS=$(echo "$DATA_BLOCK" | jq .[] | jq -r '.organizations.pageInfo.hasNextPage')
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG --- Next Page:[$NEXT_PAGE_ORGS]"
  fi

  ##############################
  # Get the Current End Cursor #
  ##############################
  END_CURSOR_ORGS=$(echo "$DATA_BLOCK" | jq .[] | jq -r '.organizations.pageInfo.endCursor')
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG --- End Cursor:[$END_CURSOR_ORGS]"
  fi

  ############################################
  # Parse all the org data out of data block #
  ############################################
  ParseOrgData "$DATA_BLOCK"

  ########################################
  # See if we need to loop for more data #
  ########################################
  if [ "$NEXT_PAGE_ORGS" == "false" ]; then
    # We have all the data, we can move on
    END_CURSOR_ORGS='null'  # Set back to null
    echo "Gathered all data from GitHub"

    #######################
    # Go through all Orgs #
    #######################
    for ORG_NAME in "${ORG_ARRAY[@]}"
    do
      echo "------------------------------------------------------"
      echo "Gathering raw information for:[$ORG_NAME]"
      ############################################
      # Set the Flag back to 0 to print Org Info #
      ############################################
      SET_ORG_INFO=0

      ###########################
      # Validate Org membership #
      ###########################
      ORG_MEMBERSHIP=$(ValidateMembership "$ORG_NAME")

      ###########################################
      # Check that we have access to go forward #
      ###########################################
      if [ "$ORG_MEMBERSHIP" -eq 0 ]; then
        # We dont have access
        echo "  - WARN! You do not have access to the Organization:[$ORG_NAME]"
        echo "  - Skipping Orgainzation..."
      else
        if [ "$ORG_MEMBERSHIP" -eq 2 ]; then
          echo "  - WARN! You only have [member] access of Organization:[$ORG_NAME]"
          echo "  - Data set may not be complete due to access rights..."
        fi
        # We have access
        ################################
        # Call GetRepoData for the Org #
        ################################
        GetRepoData "$ORG_NAME"
      fi
    done
  elif [ "$NEXT_PAGE_ORGS" == "true" ]; then
    # We need to loop through GitHub to get all repos
    echo "More pages of orgs... Looping through data with new cursor:[$END_CURSOR_ORGS]"
    #########################################
    # Call GetAllOrgs again with new cursor #
    #########################################
    GetAllOrgs
  else
    # Failing to get this value means we didnt get a good response back from GitHub
    # And it could be bad input from user, not enough access, or a bad token
    # Fail out and have user validate the info
    echo ""
    echo "######################################################"
    echo "ERROR! Failed response back from GitHub!"
    echo "Please validate your PAT, Organization, and access levels!"
    echo "######################################################"
    exit 1
  fi
}
################################################################################
#### Function ParseOrgData #####################################################
ParseOrgData()
{
  ##########################
  # Pull in the data block #
  ##########################
  PARSE_DATA=$1

  ###############
  # Debug Print #
  ###############
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG --- PARSE_DATA in ParseOrgData:[$PARSE_DATA]"
  fi

  ####################################
  # Itterate through the json object #
  ####################################
  # We need to get the sizes of the repos as well
  echo "Gathering Organization names..."
  for OBJECT in $(echo "$PARSE_DATA" | jq -r '.data.organizations.nodes | .[] | .login' ); do
    echo "Organization:[$OBJECT]"
    ###############
    # Debug print #
    ###############
    if [ $DEBUG -eq 1 ]; then
      echo "DEBUG --- OrgName:[$OBJECT]"
    fi

    #####################################
    # Skip the addition of internal org #
    #####################################
    if [[ "$OBJECT" == "github-enterprise" ]]; then
      echo "  - Skipping internal 'github-enterprise' Organization"
    else
      ############################
      # Add the Org to the Array #
      ############################
      ORG_ARRAY+=("$OBJECT")
    fi
  done
}
################################################################################
#### Function GetRepoData ######################################################
GetRepoData()
{
  # This step takes in the GitHub Organization name and queries
  # the GitHub APIv4 To gain information about that org and its repos

  ########################
  # Read in the org name #
  ########################
  ORG_NAME=$1

  ###########
  # Headers #
  ###########
  echo "------------------------------------------------------"
  echo "Gathering repo data for:[$ORG_NAME]"

  #####################################
  # Update orgname string with quotes #
  #####################################
  # Needs to be quoted to allow special chars
  O_STRING=''           # Set to empty
  O_STRING='\"'         # Adding the delimit
  O_STRING+="$ORG_NAME" # Add the name
  O_STRING+='\"'        # Add the delimit

  #####################################
  # Update the end_cursor if not null #
  #####################################
  # Needs to be quoted if not null
  END_CURSOR_STRING=''                  # Set to empty
  END_CURSOR_STRING=$END_CURSOR_REPOS
  if [[ "$END_CURSOR_REPOS" != "null" ]]; then
    END_CURSOR_STRING='\"'
    END_CURSOR_STRING+="$END_CURSOR_REPOS"
    END_CURSOR_STRING+='\"'
  fi

  ###############################
  # Call GitHub API to get info #
  ###############################
  # Note: Using the members field and not the memberswithRole field as users may not have that yet
  # This will need to be updated in the future
  DATA_BLOCK=$(curl -s -k -X POST -H "authorization: Bearer $GITHUB_PAT" -H "content-type: application/json" \
  --data '{"query":"query {\n  organization(login: '"$O_STRING"') {\n    repositories(first: '"$PAGE_SIZE"', after: '"$END_CURSOR_STRING"') {\n nodes {\n name \n createdAt\n pushedAt\n diskUsage\n }\n totalCount\n pageInfo {\n hasNextPage\n endCursor\n }\n }\n }\n}"}' \
  "$GRAPHQL_URL" 2>&1)

  #######################
  # Load the error code #
  #######################
  ERROR_CODE=$?

  ##########################
  # Check the shell return #
  ##########################
  if [ $ERROR_CODE -ne 0 ]; then
    echo "ERROR! Failed to gather data from GitHub!"
    echo "RETURN FROM COMMAND:[$DATA_BLOCK]"
    exit 1
  fi

  #########################
  # DEBUG show data block #
  #########################
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG --- DATA BLOCK:[$DATA_BLOCK]"
  fi

  ##########################
  # Get the Next Page Flag #
  ##########################
  NEXT_PAGE=$(echo "$DATA_BLOCK" | jq .[] | jq -r '.organization.repositories.pageInfo.hasNextPage')
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG --- Next Page:[$NEXT_PAGE]"
  fi

  ##############################
  # Get the Current End Cursor #
  ##############################
  END_CURSOR_REPOS=$(echo "$DATA_BLOCK" | jq .[] | jq -r '.organization.repositories.pageInfo.endCursor')
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG --- End Cursor:[$END_CURSOR_REPOS]"
  fi

  ##########################
  # Set the Org Level Info #
  ##########################
  if [ $SET_ORG_INFO -ne 1 ]; then
    #######################
    # Get the Total Repos #
    #######################
    TOTAL_REPOS=$(echo "$DATA_BLOCK" | jq .[] | jq -r '.organization.repositories.totalCount')
    ###############
    # Debug print #
    ###############
    if [ $DEBUG -eq 1 ]; then
      echo "DEBUG --- Total Repos Count:[$TOTAL_REPOS]"
    fi

    #################################
    # Set flag so we dont set again #
    #################################
    SET_ORG_INFO=1
  fi

  #############################################
  # Parse all the repo data out of data block #
  #############################################
  ParseRepoData "$DATA_BLOCK" "$ORG_NAME"

  ########################################
  # See if we need to loop for more data #
  ########################################
  if [ "$NEXT_PAGE" == "false" ]; then
    # We have all the data, we can move on
    END_CURSOR_REPOS='null' # Set it back to null
    echo "Gathered all data from GitHub"
  elif [ "$NEXT_PAGE" == "true" ]; then
    # We need to loop through GitHub to get all repos
    echo "More pages of repos... Looping through data with new cursor:[$END_CURSOR]"
    ######################################
    # Call GetRepoData again with new cursor #
    ######################################
    GetRepoData "$ORG_NAME"
  else
    # Failing to get this value means we didnt get a good response back from GitHub
    # And it could be bad input from user, not enough access, or a bad token
    # Fail out and have user validate the info
    echo ""
    echo "######################################################"
    echo "ERROR! Failed response back from GitHub!"
    echo "Please validate your PAT, Organization, and access levels!"
    echo "######################################################"
    exit 1
  fi
}
################################################################################
#### Function ParseRepoData ####################################################
ParseRepoData()
{
  ##########################
  # Pull in the data block #
  ##########################
  PARSE_DATA=$1
  ORG_NAME=$2

  ###################################
  # Iterate through the json object #
  ###################################
  # We need to get the sizes of the repos as well
  echo "Gathering Repositories and info for results file..."

  ##########################################
  # Pull out the data from the json object #
  ##########################################
  echo "$PARSE_DATA" | jq -c '.data.organization.repositories.nodes | .[]' | while read -r OBJECT; do
    REPO_NAME=$(echo "${OBJECT}" | jq -r '.name')
    CREATED_AT=$(echo "${OBJECT}" | jq -r '.createdAt')
    PUSHED_AT=$(echo "${OBJECT}" | jq -r '.pushedAt')
    DISK_USAGE=$(echo "${OBJECT}" | jq -r '.diskUsage')

    ###################
    # Print for debug #
    ###################
    if [ $DEBUG -eq 1 ]; then
      echo "DEBUG --- REPO_NAME:[$REPO_NAME]"
      echo "DEBUG --- CREATED_AT:[$CREATED_AT]"
      echo "DEBUG --- PUSHED_AT:[$PUSHED_AT]"
      echo "DEBUG --- DISK_USAGE:[$DISK_USAGE]"
    fi

    ##############
    # DEBUG info #
    ##############
    if [ $DEBUG -eq 1 ]; then
      # Run the sub to see data
      GetTimeDiff "$CREATED_AT" "$PUSHED_AT"
    fi

    ###########################
    # Get the time difference #
    ###########################
    TIME_DIFF_STRING=$(GetTimeDiff "$CREATED_AT" "$PUSHED_AT")

    ############################
    # Write to Results to file #
    ############################
    echo "$ORG_NAME,$REPO_NAME,$CREATED_AT,$PUSHED_AT,$DISK_USAGE,$TIME_DIFF_STRING" >> "$OUTPUT_FILE"
  done
}
################################################################################
#### Function GetTimeDiff ######################################################
GetTimeDiff()
{
  #####################
  # Read in variables #
  #####################
  CREATED_AT=$1
  PUSHED_AT=$2

  #####################
  # Create Local Vars #
  #####################
  CURRENT_DATE_SEC=$($DATE_CMD +'%s') # Current date in epoch
  THREE_MONTH_SEC='7884000'           # Three months worth of seconds
  SIX_MONTH_SEC='15768000'            # Six months worth of seconds
  ONE_YR_SEC='31536000'               # 1 years worth of seconds
  TWO_YR_SEC=$((ONE_YR_SEC * 2))      # 2 years worth of seconds
  FIVE_YR_SEC=$((ONE_YR_SEC * 5))     # 5 years worth of seconds
  SEVEN_YR_SEC=$((ONE_YR_SEC * 7))    # 7 years worth of seconds
  CREATE_TIME_SEC=$($DATE_CMD --date "$CREATED_AT" +'%s')   # The created time from the epoch
  PUSHED_TIME_SEC=$($DATE_CMD --date "$PUSHED_AT" +'%s')    # The pushed time from the epoch

  TIME_DIFF_SEC=$((CURRENT_DATE_SEC - PUSHED_TIME_SEC))     # Time n seconds difference
  # ACTIVE_IN_LAST_3_MONTHS,ACTIVE_IN_LAST_6_MONTHS,OVER_1YR_NO_ACTIVITY,OVER_2YR_NO_ACTIVITY,OVER_5YR_NO_ACTIVITY,OVER_7YR_NO_ACTIVITY
  ##############
  # DEBUG info #
  ##############
  if [ $DEBUG -eq 1 ]; then
    echo "DEBUG --- CREATE_TIME:[$CREATE_TIME_SEC]"
    echo "DEBUG --- PUSHED_TIME_SEC:[$PUSHED_TIME_SEC]"
    echo "DEBUG --- TIME_DIFF_SEC:[$TIME_DIFF_SEC]"
  fi

  #########
  # FLAGS #
  #########
  THREE_MONTH_FLAG='' # Flag if younger than 3 months
  SIX_MONTH_FLAG=''   # Flag if younger than 6 months
  ONE_YR_FLAG=''      # Flag if older than 1 yr
  TWO_YR_FLAG=''      # Flag if older than 2 yr
  FIVE_YR_FLAG=''     # Flag if older than 5 yr
  SEVEN_YR_FLAG=''    # Flag if older than 7 yr

  ####################################
  # Check if active in last 3 months #
  ####################################
  THREE_MONTH_AGO_DATE=$((CURRENT_DATE_SEC - THREE_MONTH_SEC))
  if [ "$PUSHED_TIME_SEC" -gt "$THREE_MONTH_AGO_DATE" ] ; then
    # Set the flag
    THREE_MONTH_FLAG="X"
  fi

  ###################################
  # Check if active in last 6 moths #
  ###################################
  SIX_MONTH_AGO_DATE=$((CURRENT_DATE_SEC - SIX_MONTH_SEC))
  if [ "$PUSHED_TIME_SEC" -gt "$SIX_MONTH_AGO_DATE" ] ; then
    # Set the flag
    SIX_MONTH_FLAG="X"
  fi

  #####################################
  # Check if no activity in last 1 yr #
  #####################################
  ONE_YEAR_AGO_DATE=$((CURRENT_DATE_SEC - ONE_YR_SEC))
  if [ "$PUSHED_TIME_SEC" -lt "$ONE_YEAR_AGO_DATE" ] ; then
    # Set the flag
    ONE_YR_FLAG="X"
  fi

  ############################
  # Check if older than 2 yr #
  ############################
  TWO_YEAR_AGO_DATE=$((CURRENT_DATE_SEC - TWO_YR_SEC))
  if [ "$PUSHED_TIME_SEC" -lt "$TWO_YEAR_AGO_DATE" ] ; then
    # Set the flag
    TWO_YR_FLAG="X"
  fi

  ############################
  # Check if older than 5 yr #
  ############################
  FIVE_YEAR_AGO_DATE=$((CURRENT_DATE_SEC - FIVE_YR_SEC))
  if [ "$PUSHED_TIME_SEC" -lt "$FIVE_YEAR_AGO_DATE" ] ; then
    # Set the flag
    FIVE_YR_FLAG="X"
  fi

  ############################
  # Check if older than 7 yr #
  ############################
  SEVEN_YEAR_AGO_DATE=$((CURRENT_DATE_SEC - SEVEN_YR_SEC))
  if [ "$PUSHED_TIME_SEC" -lt "$SEVEN_YEAR_AGO_DATE" ] ; then
    # Set the flag
    SEVEN_YR_FLAG="X"
  fi

  ########################
  # Set the print string #
  ########################
  echo "$THREE_MONTH_FLAG,$SIX_MONTH_FLAG,$ONE_YR_FLAG,$TWO_YR_FLAG,$FIVE_YR_FLAG,$SEVEN_YR_FLAG"
}
################################################################################
#### Function GetOSInfo ########################################################
GetOSInfo()
{
  ####################################################
  # Need to get the system OS so we can update calls #
  ####################################################
  if [[ "$OSTYPE" == "darwin"* ]]; then
    ###########
    # Mac OSX #
    ###########
    echo ""
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!! WARN! Some commands are Linux native!!!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo ""
    echo "You will need to install 'brew install coreutils' before running this script"
    echo "Have you installed 'coreutils'?"
    echo "(y)es (n)o, followed by [ENTER]:"
    ########################
    # Read input from user #
    ########################
    read -r INSTALL

    #######################
    # Validate user input #
    #######################
    if [[ "$INSTALL" == "yes" ]] || [[ "$INSTALL" == "y" ]]; then
      echo "Thank you, we are good to go forward..."
      # Set the date command
      DATE_CMD="gdate"
      echo "######################################################"
      echo ""
    else
      echo "Exiting script, please run command: 'brew install coreutils' before running again"
      exit 1
    fi
  elif [[ "$OSTYPE" == "win32" ]]; then
    ###########
    # Windows #
    ###########
    echo "ERROR! This script is designed to be run on MacOS or LINUX"
    echo "Please run from one of the supported operating systems."
    exit 1
  else
    #########
    # LINUX #
    #########
    echo "LinuxOS detected, we should be good to go..."
    # Set the date command
    DATE_CMD="date"
  fi
}
################################################################################
#### Function ValidateOrgListFile ##############################################
ValidateOrgListFile()
{
  # Need to validate the file contents as well as format for line endings

  ###################
  # Pull in the var #
  ###################
  ORG_LIST=$1

  #################
  # Flag for file #
  #################
  CHECK_FILE=0

  ######################################
  # check if we have just an enter key #
  ######################################
  if [ -z "$ORG_LIST" ]; then
    # Empty, were checking everything
    echo "You have elected to check all available Organizations..."
  ##############################
  # Check that the file exists #
  ##############################
  elif [ ! -f "$ORG_LIST" ]; then
    # File not found
    echo "ERROR! Failed to validate file at:[$ORG_LIST]"
    echo "Please ensure you give full path and name of file!"
    exit 1
  else
    ##############################
    # We have a file to validate #
    ##############################
    CHECK_FILE=1
  fi

  ##############################
  # Check the contents of file #
  ##############################
  echo "Validating file and contents..."
  if [ $CHECK_FILE -eq 1 ]; then
    while IFS= read -r ORG_NAME;
    do
      # Clean line endings
      ORG_NAME=$(echo "${ORG_NAME}" | tr -d '\15\32')
      # Push to array
      ORG_ARRAY+=("$ORG_NAME")
    done < "$ORG_LIST"

    ###################################
    # Validate the Array is not empty #
    ###################################
    LENGTH=${#ORG_ARRAY[@]}

    ########################
    # Check for empty file #
    ########################
    if [ "$LENGTH" -lt 1 ]; then
      echo "ERROR! You gave me an empty file!"
      echo "Either add Organizations to the file or hit [ENTER] to query all available"
      exit 1
    else
      echo "File passed basic validation..."
    fi
  fi
}
################################################################################
#### Function ValidateMembership ###############################################
ValidateMembership()
{
  ####################
  # Pull in Org Name #
  ####################
  ORG_NAME=$1

  ##################
  # Get membership #
  ##################
  MEMBERSHIP_RESPONSE=$(curl -kw '%{http_code}' -s -X GET \
  --url "${GITHUB_API_URL}/orgs/${ORG_NAME}/memberships/${USER_LOGIN}" \
  --header "authorization: Bearer ${GITHUB_PAT}")

  ############################
  # Read in the data to vars #
  ############################
  MEMBERSHIP_RESPONSE_CODE="${MEMBERSHIP_RESPONSE:(-3)}"
  MEMBERSHIP_DATA="${MEMBERSHIP_RESPONSE::${#MEMBERSHIP_RESPONSE}-4}"

  ##########################
  # Check if member of org #
  ##########################
  if [[ "$MEMBERSHIP_RESPONSE_CODE" != "200" ]]; then
    ################
    # Not a member #
    ################
    echo "0"
    return "0"
  else
    MEMBERSHIP_STATUS=$(echo "${MEMBERSHIP_DATA}" | jq -r '.role')
    if [[ ${MEMBERSHIP_STATUS} = "admin" ]]; then
      ################
      # Are an admin #
      ################
      echo "1"
      return "1"
    else
      ##############################
      # Are a member but not admin #
      ##############################
      echo "2"
      return "2"
    fi
  fi
}
################################################################################
############################## MAIN ############################################
################################################################################

##########
# Header #
##########
Header

###############
# Get OS Info #
###############
GetOSInfo

###################
# Get GitHub Info #
###################
GetGitHubInfo

#########################
# Validate JQ installed #
#########################
ValidateJQ

########################
# Validate Output File #
########################
ValidateOutputFile

#########################################################
# ee if we need to find info for single org or all orgs #
#########################################################
if [[ "$GITHUB_API_URL" == "https://api.github.com" ]]; then
  ###########
  # Get Org #
  ###########
  GetOrg
else
  #######################
  # Get GitHub Org Data #
  #######################
  GetAllOrgs
fi

##########
# Footer #
##########
Footer

