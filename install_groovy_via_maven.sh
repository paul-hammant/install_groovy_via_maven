#!/bin/bash

# From https://github.com/paul-hammant/install_groovy_via_maven
# v1.0

# Stop the script immediately if any command exits with a non-zero status
set -e

# Variables
GROUP_ID="com.yourcompany.app"
ARTIFACT_ID="groovy-bootstrap"
DEFAULT_VERSION="4.0.22"  # Default Groovy version
VERSION=${1:-$DEFAULT_VERSION}  # Use the first argument as version if provided, otherwise use default
WORK_DIR=$(pwd)
TEMP_DIR=$(mktemp -d)

# Function to detect the local Maven repository path
detect_m2_repo() {
    # Extract the local repository path from settings.xml if it exists
    if [ -f "$HOME/.m2/settings.xml" ]; then
        M2_REPO=$(sed -n 's|.*<localRepository>\(.*\)</localRepository>.*|\1|p' "$HOME/.m2/settings.xml" | sed 's/^[ \t]*//;s/[ \t]*$//')
    fi
    
    # Fallback to the default path if not set or if the result is empty
    if [ -z "$M2_REPO" ]; then
        M2_REPO="$HOME/.m2/repository"
    fi
    
    echo "$M2_REPO"
}

# Function to detect the Maven executable directory
detect_mvn_dir() {
    # Use `which` to find the location of the mvn binary
    MVN_DIR=$(dirname "$(which mvn)")
    
    echo "$MVN_DIR"
}

# Function to convert Windows-style paths to Unix-style using sed
convert_to_unix_path() {
    local path_entries="$1"
    echo "$path_entries" | sed 's|\\|/|g' | sed 's|C:|/c|g' # Convert backslashes to slashes and 'C:' to '/c'
}

# Step 1: Detect the Maven repository path
M2_REPO=$(detect_m2_repo)
echo "Using Maven repository at: $M2_REPO"

# Step 2: Detect the Maven directory
MVN_DIR=$(detect_mvn_dir)
echo "Using Maven directory: $MVN_DIR"

# Step 3: Create a temporary Maven project
cd $TEMP_DIR
mvn archetype:generate -DgroupId=$GROUP_ID -DartifactId=$ARTIFACT_ID -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false
cd $ARTIFACT_ID

# Step 4: Modify the pom.xml to add specific Groovy dependencies
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
    </dependency>' $POM_FILE

# Step 5: Force Maven to resolve dependencies and build classpath
mvn dependency:resolve -U

# Step 6: Use Maven to resolve and build the classpath
CLASSPATH=$(mvn dependency:build-classpath -Dmdep.pathSeparator=: -DincludeScope=runtime | grep -v '\[' | tail -n 1)

if [ -z "$CLASSPATH" ]; then
    echo "Error: Failed to build classpath. Please check Maven output."
    exit 1
fi

# Convert the CLASSPATH to Unix-style paths
UNIX_CLASSPATH=$(convert_to_unix_path "$CLASSPATH")

# Step 7: Create the 'groovy' script with the converted classpath
cat <<EOL > groovy
#!/bin/bash

# Hardcoded classpath with all the necessary Groovy JARs
CLASSPATH="$UNIX_CLASSPATH"
echo "Using classpath: \$CLASSPATH"

# Execute the Groovy script, passing all arguments
java -cp "\$CLASSPATH" org.codehaus.groovy.tools.GroovyStarter --main groovy.ui.GroovyMain "\$@"
EOL

chmod +x groovy

# Step 8: Attempt to move the script to the directory containing the `mvn` executable
mv groovy "$MVN_DIR/"

# Step 9: Create a litmus test Groovy script to verify installation
cat <<'EOF' > test_groovy_install.groovy
println "Groovy is installed - printed from a .groovy script to test installation"
EOF

# Step 10: Run the litmus test
groovy test_groovy_install.groovy

# Step 11: Clean up the test script
rm test_groovy_install.groovy

# Step 12: Clean up the temporary Maven project
rm -rf $TEMP_DIR

echo "Groovy environment setup complete - \`groovy\` executable placed in $MVN_DIR"
