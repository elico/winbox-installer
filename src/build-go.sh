#!/bin/sh

set -e

cd "$(dirname "$0")"

export CGO_ENABLED=0 GOOS=windows GOARCH=amd64 GOTOOLCHAIN=local

[ -f go.mod ] || go mod init connect-to-mt
grep -q golang.org/x/sys go.mod || go get golang.org/x/sys@v0.36.0

go mod tidy
go build -o connect-to-mt-64-go.exe connect-to-mt.go
