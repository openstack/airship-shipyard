#!/bin/bash
# Copyright 2018 AT&T Intellectual Property.  All other rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# This is a common script that is used by the deploy_site, update_site
# and redeploy_server scripts

set -ex

check_timeout_counter() {

    # Check total elapsed time
    # The default time out is set to 1.5 hr
    if [[ $counter -ge $max_count ]]; then
        echo 'Worflow Execution Timed Out!'
        break
    fi
}

run_action () {

    # Define Variables
    action=$1
    server=$2

    # Define Color
    NC='\033[0m'
    RED='\033[0;31m'
    GREEN='\033[0;32m'

    # Execute action
    echo -e "Execute ${action} Dag...\n"

    # Note that deploy and update site do not require additional parameter
    # to be passed in while redeploy_server requires user to indicate which
    # server to redeploy
    if ! [[ ${server} ]] && [[ ${action} ]]; then
        shipyard create action ${action}
    elif [[ ${action} == 'redeploy_server' && ${server} ]]; then
        shipyard create action redeploy_server --param="server-name=${server}"
    else
        echo "Invalid Input!"
        exit 1
    fi

    # The status or lifecycle phase of an action can be
    #
    # 1) Pending - The action is scheduled or preparing for execution.
    # 2) Processing - The action is underway.
    # 3) Complete - The action has completed successfully.
    # 4) Failed - The action has encountered an error, and has failed.
    # 5) Paused - The action has been paused by a user.
    # 6) Unknown (*) - Unknown State for corner cases
    # 7) null - We will end up with a `null` response from Shipyard if we
    #           query the status of the task with an expired keystone token.
    #           Note that this should never happen if we use Shipyard CLI as
    #           new token is retrieved each time. Description for state 'null'
    #           is included here for information only.
    #
    # Print current list of actions in Shipyard
    shipyard get actions

    # Retrieve the ID of the action that is currently being executed
    echo -e "Retrieving Action ID...\n"
    action_id=`shipyard get actions | grep ${action} | grep -i Processing | awk '{print $2}'`

    if ! [[ ${action_id} ]]; then
        echo "Unable to Retrieve Action ID!"
        exit 1
    else
        echo "The Action ID is" ${action_id}
    fi

    # Initialize 'action_lifecycle' to 'Pending'
    action_lifecycle="Pending"

    # Initialize counter to 1
    counter=1

    while true;
    do
        # Get Current State of Action Lifecycle
        describe_action=`shipyard describe ${action_id}`
        action_lifecycle=`echo ${describe_action} | awk '{print $6}'`

        if [[ $action_lifecycle == "Complete" ]]; then
            echo -e '\nSuccessfully performed' ${action}
            echo -e '\n'
            break
        fi

        # Check Dag state
        if [[ $action_lifecycle == "Failed" ]] || [[ $action_lifecycle == "Paused" ]] || \
           [[ $action_lifecycle == "Unknown"* ]] || [[ $action_lifecycle == "null" ]]; then
            echo -e "Dag Execution is in" ${RED}$action_lifecycle${NC} "state\n"
            break
        else
            echo -e "Dag Execution is in" ${GREEN}$action_lifecycle${NC} "state\n"

            # Back off between each iteration
            echo -e "Back Off for $query_time seconds...\n"
            sleep $query_time

            # Step counter and check the timeout counter
            ((counter++))
            check_timeout_counter
        fi
    done

    # Return exit code so that we can use it to determine the final
    # state of the workflow
    if [[ $action_lifecycle == "Complete" ]]; then
        exit 0
    else
        exit 1
    fi
}

# Note that we will need to execute the deckhand_load_yaml
# script first before the deploy_site script
# Check to ensure that the Shipyard CLI has been installed on
# the Genesis host during the deckhand YAML load phase. Exit
# script if Shipyard CLI is not installed.
command -v shipyard >/dev/null 2>&1 || { echo >&2 "Please install Shipyard CLI before executing the script."; exit 1; }

# Calls 'run_action' function
run_action "${@}"