#!/bin/bash
echo "Waiting for build to finish..."
while pgrep xcodebuild > /dev/null; do
    sleep 3
done
echo "Deploying..."
if grep -q "BUILD SUCCEEDED" build_final2.txt; then
    cp -f /Users/niltonperimneto/Library/Developer/Xcode/DerivedData/Whisky-bwvrnhfvocjgfngpdxazkxvsdyon/Build/Products/Release/Whisky.app/Contents/MacOS/Whisky "/Applications/Whisky Preview.app/Contents/MacOS/Whisky"
    echo "Launching..."
    open "/Applications/Whisky Preview.app"
    echo "Done!"
else
    echo "Build failed! See build_final2.txt"
    exit 1
fi
