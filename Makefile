SWIFT_FORMAT_PATHS := Sources Tests Package.swift
SWIFT_STRICT_FLAGS := -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors

.DEFAULT_GOAL := check

.PHONY: check build build-release format lint test

check: lint build build-release test

build:
	swift build $(SWIFT_STRICT_FLAGS)

build-release:
	swift build -c release $(SWIFT_STRICT_FLAGS)

format:
	swift format format --recursive --in-place $(SWIFT_FORMAT_PATHS)

lint:
	swift format lint --recursive --strict $(SWIFT_FORMAT_PATHS)

test:
	swift test $(SWIFT_STRICT_FLAGS)
