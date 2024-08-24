#!/bin/bash

# Stop the script immediately if any command exits with a non-zero status
set -e

# Variables
GROUP_ID="com.yourcompany.app"
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

    echo "$M2_REPO"
}

# Function to convert Windows-style paths to Unix-style using sed
convert_to_unix_path() {
    local path_entries="$1"
    echo "$path_entries" | sed 's|\\|/|g' | sed 's|C:|/c|g'
}

# Step 1: Detect the Maven repository path
M2_REPO=$(detect_m2_repo)
echo "Using Maven repository at: $M2_REPO"

# Step 2: Create a temporary Maven project
cd $TEMP_DIR
mvn archetype:generate -DgroupId=$GROUP_ID -DartifactId=$ARTIFACT_ID -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false
cd $ARTIFACT_ID

# Step 3: Modify the pom.xml to add specific Groovy dependencies
POM_FILE="pom.xml"
sed -i '/<dependencies>/a \
    <dependency>\
        <groupId>org.apache.groovy</groupId>\
        <artifactId>groovy</artifactId>\
        <version>'$VERSION'</version>\
    </dependency>\
    <dependency>\
        <groupId>org.apache.groovy</groupId>\
        <artifactId>groovy-json</artifactId>\
        <version>'$VERSION'</version>\
    </dependency>\
    <dependency>\
        <groupId>org.apache.groovy</groupId>\
        <artifactId>groovy-xml</artifactId>\
        <version>'$VERSION'</version>\
    </dependency>\
    <dependency>\
        <groupId>org.apache.groovy</groupId>\
        <artifactId>groovy-sql</artifactId>\
        <version>'$VERSION'</version>\
    </dependency>\
    <dependency>\
        <groupId>org.apache.groovy</groupId>\
        <artifactId>groovy-nio</artifactId>\
        <version>'$VERSION'</version>\
    </dependency>\
    <dependency>\
        <groupId>org.apache.ivy</groupId>\
        <artifactId>ivy</artifactId>\
        <version>2.5.0</version>\
    </dependency>' $POM_FILE

# Step 4: Force Maven to resolve dependencies and build classpath
mvn dependency:resolve -U

# Step 5: Use Maven to resolve and build the classpath
CLASSPATH=$(mvn dependency:build-classpath -Dmdep.pathSeparator=: -DincludeScope=runtime | grep -v '\[' | tail -n 1)

if [ -z "$CLASSPATH" ]; then
    echo "Error: Failed to build classpath. Please check Maven output."
    exit 1
fi

# Ensure the classpath uses the correct user's home directory
UNIX_CLASSPATH=$(convert_to_unix_path "$CLASSPATH")

# Step 6: Create the 'groovy.sh' script with the converted classpath
GROOVY_SCRIPT="$WORK_DIR/groovy.sh"
cat <<EOL > "$GROOVY_SCRIPT"
#!/bin/bash

# Hardcoded classpath with all the necessary Groovy JARs
CLASSPATH="$UNIX_CLASSPATH"
echo "Using classpath: \$CLASSPATH"

# Execute the Groovy script, passing all arguments
java -cp "\$CLASSPATH" org.codehaus.groovy.tools.GroovyStarter --main groovy.ui.GroovyMain "\$@"
EOL

chmod +x "$GROOVY_SCRIPT"

# Confirm creation of groovy.sh
echo "groovy.sh script created at: $GROOVY_SCRIPT"

# Step 7: Clean up the temporary Maven project
rm -rf $TEMP_DIR

echo "Groovy environment setup complete - \`groovy.sh\` executable created in the current directory."
