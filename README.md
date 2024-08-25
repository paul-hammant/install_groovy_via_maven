# Install Groovy Via Maven

## Prerequisites

Your env is bash on Linux or GitBash on Windows.  Mac: not tested.

You already had Maven setup and working in the same environment.

## Your rationale

You don't have a Goovy installer, but you do have a working Maven environment

## Instructions

Just run the `install_groovy_via_maven.sh` script in bash - optional groovy version string as first arg. Script can be run again and again, fairly safely.  

## Bugs/Features/TODO

1. Grapes is not working in GitBash on Windows for me: https://issues.apache.org/jira/projects/GROOVY/issues/GROOVY-11454
2. Do something better than hard code Ivy 2.5.2


