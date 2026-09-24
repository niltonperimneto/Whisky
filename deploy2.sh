#!/bin/bash
echo "Waiting for build to finish..."
while pgrep xcodebuild > /dev/null; do
    sleep 3
done
echo "Deploying..."
if grep -q "BUILD SUCCEEDED" build_final5.txt; then
    rm -rf "/Applications/Whisky Preview.app"
    cp -R "/Users/niltonperimneto/Library/Developer/Xcode/DerivedData/Whisky-bwvrnhfvocjgfngpdxazkxvsdyon/Build/Products/Release/Whisky Preview.app" "/Applications/"
    echo "Launching..."
    open "/Applications/Whisky Preview.app"
    echo "Done!"
else
    echo "Build failed!"
    exit 1
fi
