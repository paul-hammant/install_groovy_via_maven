#!/bin/bash

# From https://github.com/paul-hammant/install_groovy_via_maven
# v1.0.4

# Stop the script immediately if any command exits with a non-zero status
set -e

# Variables
GROUP_ID="not-important"
ARTIFACT_ID="groovy-bootstrap"
DEFAULT_VERSION="4.0.22"  # Default Groovy version
VERSION=${1:-$DEFAULT_VERSION}  # Use the first argument as version if provided, otherwise use default
USER_HOME="$HOME"
WORK_DIR=$(pwd)
TEMP_DIR=$(mktemp -d)

# Function to detect the local Maven repository path
detect_m2_repo() {
    if [ -f "$USER_HOME/.m2/settings.xml" ]; then
        M2_REPO=$(sed -n 's|.*<localRepository>\(.*\)</localRepository>.*|\1|p' "$USER_HOME/.m2/settings.xml" | sed 's/^[ \t]*//;s/[ \t]*$//')
    fi

    if [ -z "$M2_REPO" ]; then
        M2_REPO="$USER_HOME/.m2/repository"
    fi

    # Convert Windows-style paths to Unix-style for GitBash
    M2_REPO=$(echo "$M2_REPO" | sed 's|\\|/|g' | sed 's|C:|/c|g')

    # Add file:// prefix if it's a local path
    M2_REPO="file://$M2_REPO"

    echo "$M2_REPO"
}

# Function to extract the corporate Nexus repository URL from Maven settings.xml
detect_maven_repository_url() {
    if [ -f "$USER_HOME/.m2/settings.xml" ]; then
        # Extract URL from a mirror section if it's defined
        USE_THIS_MAVEN_REPO_URL=$(sed -n '/<mirror>/,/<\/mirror>/p' "$USER_HOME/.m2/settings.xml" | sed -n 's|.*<url>\(.*\)</url>.*|\1|p')
    fi

    # If not found, use Maven Central as a default
    if [ -z "$USE_THIS_MAVEN_REPO_URL" ]; then
        USE_THIS_MAVEN_REPO_URL="https://repo.maven.apache.org/maven2"
    fi

    echo "$USE_THIS_MAVEN_REPO_URL"
}

# Function to extract server credentials from Maven settings.xml using grep and sed
extract_maven_server_credentials() {
    local settings_file="$USER_HOME/.m2/settings.xml"
    local username=""
    local password=""

    if [ -f "$settings_file" ]; then
        username=$(grep -m 1 "<username>" "$settings_file" | sed 's|.*<username>\(.*\)</username>.*|\1|')
        password=$(grep -m 1 "<password>" "$settings_file" | sed 's|.*<password>\(.*\)</password>.*|\1|')
    fi

    echo "$username" "$password"
}

# Step 1: Detect the Maven repository path
M2_REPO=$(detect_m2_repo)
echo "Using Maven repository at: $M2_REPO"

# Step 2: Detect the Corporate Nexus URL
USE_THIS_MAVEN_REPO_URL=$(detect_maven_repository_url)
echo "Using Maven repository at: $USE_THIS_MAVEN_REPO_URL"

# Step 3: Extract server credentials (if needed) and append to URL
read USERNAME PASSWORD <<< $(extract_maven_server_credentials)

# If username and password are available, embed them into the repository URL
if [ -n "$USERNAME" ] && [ -n "$PASSWORD" ]; then
    AUTHENTICATED_MAVEN_REPO_URL=$(echo "$USE_THIS_MAVEN_REPO_URL" | sed "s|https://|https://$USERNAME:$PASSWORD@|")
else
    AUTHENTICATED_MAVEN_REPO_URL="$USE_THIS_MAVEN_REPO_URL"
fi

echo "Using authenticated Maven repository URL: $AUTHENTICATED_MAVEN_REPO_URL"

# Step 4: Create a temporary Maven project
cd $TEMP_DIR
mvn archetype:generate -DgroupId=$GROUP_ID -DartifactId=$ARTIFACT_ID -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false
cd $ARTIFACT_ID

# Step 5: Modify the pom.xml to add specific Groovy dependencies
POM_FILE="pom.xml"
sed -i '/<dependencies>/a \
    <dependency><groupId>org.apache.groovy</groupId><artifactId>groovy</artifactId><version>'$VERSION'</version></dependency>\
    <dependency><groupId>org.apache.groovy</groupId><artifactId>groovy-json</artifactId><version>'$VERSION'</version></dependency>\
    <dependency><groupId>org.apache.groovy</groupId><artifactId>groovy-xml</artifactId><version>'$VERSION'</version></dependency>\
    <dependency><groupId>org.apache.groovy</groupId><artifactId>groovy-nio</artifactId><version>'$VERSION'</version></dependency>\
    <dependency><groupId>org.apache.groovy</groupId><artifactId>groovy-sql</artifactId><version>'$VERSION'</version></dependency>\
    <dependency><groupId>org.apache.ivy</groupId><artifactId>ivy</artifactId><version>2.5.0</version></dependency>' $POM_FILE

# Step 6: Force Maven to resolve dependencies and build classpath
mvn dependency:resolve -U

# Step 7: Use Maven to resolve and build the classpath
CLASSPATH=$(mvn dependency:build-classpath -Dmdep.pathSeparator=: -DincludeScope=runtime | grep -v '\[' | tail -n 1)

if [ -z "$CLASSPATH" ]; then
    echo "Error: Failed to build classpath. Please check Maven output."
    exit 1
fi

# Ensure the classpath uses the correct user's home directory
UNIX_CLASSPATH=$(echo "$CLASSPATH" | sed 's|\\|/|g' | sed 's|C:|/c|g')

# Step 8: Create the grapeConfig.xml in ~/.groovy/
GRAPE_CONFIG_DIR="$USER_HOME/.groovy"
GRAPE_CONFIG_FILE="$GRAPE_CONFIG_DIR/grapeConfig.xml"

mkdir -p "$GRAPE_CONFIG_DIR"

cat <<EOL > "$GRAPE_CONFIG_FILE"
<ivysettings>
  <settings defaultResolver="downloadGrapes"/>
  <resolvers>
    <chain name="downloadGrapes" returnFirst="true">
      <filesystem name="cachedGrapes">
        <ivy pattern="\${user.home}/.groovy/grapes/[organisation]/[module]/ivy-[revision].xml"/>
        <artifact pattern="\${user.home}/.groovy/grapes/[organisation]/[module]/[type]s/[artifact]-[revision](-[classifier]).[ext]"/>
      </filesystem>
      <ibiblio name="localm2" root="$M2_REPO" checkmodified="true" changingPattern=".*" changingMatcher="regexp" m2compatible="true"/>
      <!-- TODO: add 'endorsed groovy extensions' resolver here -->
      <ibiblio name="ibiblio" root="$AUTHENTICATED_MAVEN_REPO_URL" m2compatible="true" />
    </chain>
  </resolvers>
</ivysettings>
EOL

echo "grapeConfig.xml has been created at $GRAPE_CONFIG_FILE"

# Step 9: Create the 'groovy.sh' script with the converted classpath and JVM -D parameters
GROOVY_SCRIPT="$WORK_DIR/groovy.sh"
cat <<EOL > "$GROOVY_SCRIPT"
#!/bin/bash

# This script made from an invocation of https://github.com/paul-hammant/install_groovy_via_maven, or a derivative

# Hardcoded classpath with all the necessary Groovy JARs
CLASSPATH="$UNIX_CLASSPATH"
# echo "Using classpath: \$CLASSPATH"

# JVM parameters including -D for Grape config file and Ivy debug logging
JAVA_OPTS="-Dgrape.config=$GRAPE_CONFIG_FILE"
# -Divy.message.logger.level=4

# Execute the Groovy script, passing all arguments
java \$JAVA_OPTS -cp "\$CLASSPATH" org.codehaus.groovy.tools.GroovyStarter --main groovy.ui.GroovyMain "\$@"
EOL

chmod +x "$GROOVY_SCRIPT"

# Step 10: Create a litmus test Groovy script to verify Grape is working
LITMUS_TEST_GROOVY_SCRIPT="test_grape_install.groovy"
cat <<'EOF' > "$LITMUS_TEST_GROOVY_SCRIPT"
@Grab(group='org.apache.commons', module='commons-lang3', version='3.12.0')
import org.apache.commons.lang3.StringUtils

println "Groovy Test: it works!"
println "Groovy-Grapes Test: Reversed 'Groovy' (via org.apache.commons:commons-lang3 StringUtils.reverse(str)) is: " + StringUtils.reverse("Groovy")
EOF

# Debugging: Check the directory and file permissions
# echo "Current directory: $(pwd)"
# echo "Contents of directory:"
# ls -al

echo "Executing groovy.sh for a litmus test of Groovy and Groovy-Grapes ..."
"$WORK_DIR/groovy.sh" "$LITMUS_TEST_GROOVY_SCRIPT"

# Step 11: Clean up the test script
rm "$LITMUS_TEST_GROOVY_SCRIPT"

# Step 12: Clean up the temporary Maven project
rm -rf $TEMP_DIR

echo "Groovy environment setup complete - \`groovy.sh\` executable created in the current directory."
