#!/usr/bin/env bash

APPNAME="voter"

#set -o nounset #exit if an unset variable is used
set -o errexit #exit on any single command fail

# find voltdb binaries in either installation or distribution directory.
if [ -n "$(which voltdb 2> /dev/null)" ]; then
    VOLTDB_BIN=$(dirname "$(which voltdb)")
else
    VOLTDB_BIN="$(dirname $(dirname $(pwd)))/bin"
    echo "The VoltDB scripts are not in your PATH."
    echo "For ease of use, add the VoltDB bin directory: "
    echo
    echo $VOLTDB_BIN
    echo
    echo "to your PATH."
    echo
fi
# installation layout has all libraries in $VOLTDB_ROOT/lib/voltdb
if [ -d "$VOLTDB_BIN/../lib/voltdb" ]; then
    VOLTDB_BASE=$(dirname "$VOLTDB_BIN")
    VOLTDB_LIB="$VOLTDB_BASE/lib/voltdb"
    VOLTDB_VOLTDB="$VOLTDB_LIB"
# distribution layout has libraries in separate lib and voltdb directories
else
    VOLTDB_BASE=$(dirname "$VOLTDB_BIN")
    VOLTDB_LIB="$VOLTDB_BASE/lib"
    VOLTDB_VOLTDB="$VOLTDB_BASE/voltdb"
fi

APPCLASSPATH=$CLASSPATH:$({ \
    \ls -1 "$VOLTDB_VOLTDB"/voltdb-*.jar; \
    \ls -1 "$VOLTDB_LIB"/*.jar; \
    \ls -1 "$VOLTDB_LIB"/extension/*.jar; \
} 2> /dev/null | paste -sd ':' - )
CLIENTCLASSPATH=$CLASSPATH:$({ \
    \ls -1 "$VOLTDB_VOLTDB"/voltdbclient-*.jar; \
    \ls -1 "$VOLTDB_LIB"/commons-cli-1.2.jar; \
} 2> /dev/null | paste -sd ':' - )
VOLTDB="$VOLTDB_BIN/voltdb"
LOG4J="$VOLTDB_VOLTDB/log4j.xml"
LICENSE="$VOLTDB_VOLTDB/license.xml"
HOST="localhost"

# remove build artifacts
function clean() {
    rm -rf debugoutput $APPNAME-procs.jar voltdbroot log catalog-report.html \
         statement-plans procedures/voter/*.class client/voter/*.class
}

# compile the source code for procedures and the client
function srccompile() {
    javac -target 1.7 -source 1.7 -classpath $APPCLASSPATH \
        client/voter/*.java \
        procedures/voter/*.java
    jar cf $APPNAME-procs.jar -C procedures voter
}

# run the voltdb server locally
function server() {
    echo "Starting the VoltDB server."
    echo "To perform this action manually, use the command line: "
    echo
    echo "voltdb create -d deployment.xml -l $LICENSE -H $HOST"
    echo
    $VOLTDB create -d deployment.xml -l $LICENSE -H $HOST
}

# load schema and procedures
function init() {
    srccompile
    $VOLTDB_BIN/sqlcmd < ddl.sql
}

function nohup_server() {
    srccompile
    # run the server
    nohup $VOLTDB create -d deployment.xml -l $LICENSE -H $HOST $APPNAME.jar > nohup.log 2>&1 &
    $VOLTDB_BIN/sqlcmd < ddl.sql
}

# run the voltdb server locally
function rejoin() {
    # run the server
    $VOLTDB rejoin -H $HOST -d deployment.xml -l $LICENSE
}

# run the client that drives the example
function client() {
    async-benchmark
}

# Asynchronous benchmark sample
# Use this target for argument help
function async-benchmark-help() {
    srccompile
    java -classpath client:$CLIENTCLASSPATH voter.AsyncBenchmark --help
}

# latencyreport: default is OFF
# ratelimit: must be a reasonable value if lantencyreport is ON
# Disable the comments to get latency report
function async-benchmark() {
    srccompile
    java -classpath client:$CLIENTCLASSPATH -Dlog4j.configuration=file://$LOG4J \
        voter.AsyncBenchmark \
        --displayinterval=5 \
        --warmup=5 \
        --duration=120 \
        --servers=localhost:21212 \
        --contestants=6 \
        --maxvotes=2
#        --latencyreport=true \
#        --ratelimit=100000
}

function simple-benchmark() {
    srccompile
    java -classpath client:$CLIENTCLASSPATH -Dlog4j.configuration=file://$LOG4J \
        voter.SimpleBenchmark localhost
}

# Multi-threaded synchronous benchmark sample
# Use this target for argument help
function sync-benchmark-help() {
    srccompile
    java -classpath $CLIENTCLASSPATH:client voter.SyncBenchmark --help
}

function sync-benchmark() {
    srccompile
    java -classpath client:$CLIENTCLASSPATH -Dlog4j.configuration=file://$LOG4J \
        voter.SyncBenchmark \
        --displayinterval=5 \
        --warmup=5 \
        --duration=120 \
        --servers=localhost:21212 \
        --contestants=6 \
        --maxvotes=2 \
        --threads=40
}

# JDBC benchmark sample
# Use this target for argument help
function jdbc-benchmark-help() {
    srccompile
    java -classpath client:$CLIENTCLASSPATH voter.JDBCBenchmark --help
}

function jdbc-benchmark() {
    srccompile
    java -classpath client:$CLIENTCLASSPATH -Dlog4j.configuration=file://$LOG4J \
        voter.JDBCBenchmark \
        --displayinterval=5 \
        --duration=120 \
        --maxvotes=2 \
        --servers=localhost:21212 \
        --contestants=6 \
        --threads=40
}

# The following two demo functions are used by the Docker package. Don't remove.
# compile the catalog and client code
function demo-compile() {
    catalog
}

function demo() {
    echo "starting server in background..."
    nohup_server
    sleep 10
    echo "starting client..."
    client

    echo
    echo When you are done with the demo database, \
        remember to use \"$VOLTDB_BIN/voltadmin shutdown\" to stop \
        the server process.
}

function help() {
    echo "Usage: ./run.sh {clean|server|init|client|async-benchmark|aysnc-benchmark-help|...}"
    echo "       {...|sync-benchmark|sync-benchmark-help|jdbc-benchmark|jdbc-benchmark-help}"
}

# Run the target passed as the first arg on the command line
# If no first arg, run server
if [ $# -gt 1 ]; then help; exit; fi
if [ $# = 1 ]; then $1; else server; fi
