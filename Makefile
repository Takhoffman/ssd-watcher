.PHONY: generate build test clean

generate:
	xcodegen generate

build: generate
	xcodebuild -project SSDWatcher.xcodeproj -scheme SSDWatcher -configuration Debug -derivedDataPath /tmp/SSDWatcherDerivedData CODE_SIGNING_ALLOWED=NO build

test: generate
	xcodebuild -project SSDWatcher.xcodeproj -scheme SSDWatcher -configuration Debug -derivedDataPath /tmp/SSDWatcherDerivedData CODE_SIGNING_ALLOWED=NO test

clean:
	xcodebuild -project SSDWatcher.xcodeproj -scheme SSDWatcher clean
