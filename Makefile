.PHONY: generate validate build test check clean

generate:
	xcodegen generate

validate:
	scripts/validate.sh

build: generate
	xcodebuild -project SSDWatcher.xcodeproj -scheme SSDWatcher -configuration Debug -derivedDataPath /tmp/SSDWatcherDerivedData CODE_SIGNING_ALLOWED=NO build

test: generate
	xcodebuild -project SSDWatcher.xcodeproj -scheme SSDWatcher -configuration Debug -derivedDataPath /tmp/SSDWatcherDerivedData CODE_SIGNING_ALLOWED=NO test

check: validate test

clean:
	xcodebuild -project SSDWatcher.xcodeproj -scheme SSDWatcher clean
