# MacPhoneMirror development helpers
#
# Requires SwiftLint and SwiftFormat (install once):
#   brew install swiftlint swiftformat
#
# Available targets:
#   make lint             Run SwiftLint
#   make format           Format all Swift code with SwiftFormat
#   make format-lint      Format, then run SwiftLint
#   make check            Run lint + format (read-only) check (CI-friendly)

.PHONY: lint format format-lint check

# --disable-sourcekit lets SwiftLint run without a full Xcode install
# (e.g. Command Line Tools only). On machines with Xcode, the extra
# SourceKit-backed rules are skipped gracefully by SwiftLint itself.
SWIFTLINT_FLAGS := --disable-sourcekit --reporter xcode

lint:
	@which swiftlint >/dev/null 2>&1 || (echo "SwiftLint not installed. Run: brew install swiftlint" && exit 1)
	swiftlint lint $(SWIFTLINT_FLAGS)

format:
	@which swiftformat >/dev/null 2>&1 || (echo "SwiftFormat not installed. Run: brew install swiftformat" && exit 1)
	swiftformat .

format-lint: format lint

check:
	@which swiftlint >/dev/null 2>&1 || (echo "SwiftLint not installed. Run: brew install swiftlint" && exit 1)
	@which swiftformat >/dev/null 2>&1 || (echo "SwiftFormat not installed. Run: brew install swiftformat" && exit 1)
	swiftlint lint $(SWIFTLINT_FLAGS)
	swiftformat --lint .
