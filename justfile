default:
    just --list

format:
    swift format format --recursive --in-place Sources Tests Package.swift

lint:
    swift format lint --recursive --strict Sources Tests Package.swift

test:
    swift test

coverage:
    swift test --enable-code-coverage
    xcrun llvm-cov report .build/debug/LicenseKitPackageTests.xctest/Contents/MacOS/LicenseKitPackageTests -instr-profile .build/debug/codecov/default.profdata -ignore-filename-regex='Tests|\.build'

check: lint test

clean:
    swift package clean
    rm -rf .build .swiftpm
