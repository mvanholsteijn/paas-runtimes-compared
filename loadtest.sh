#!/bin/bash
if nc 127.0.0.1 1337 </dev/null > /dev/null ; then
	echo ERROR: Server is still running on port 1337
	exit 1
fi

if [ "$1" == "go" ] ; then
	CONTEXTROOT=/
	go build simpleserver.go & 
	./simpleserver & 
elif [ "$1" == "java" ] ; then
	CONTEXTROOT=/helloworld
	if [ ! -f dropwizard-helloworld/target/dropwizard-helloworld-*-SNAPSHOT.jar ] ; then
		( cd dropwizard-helloworld ;
			mvn -DskipTests package
		)
		if [ ! -f dropwizard-helloworld/target/dropwizard-helloworld-*-SNAPSHOT.jar ] ; then
			echo ERROR : Failed to build dropwizard application. check output.
			exit 1
		fi
	fi
	java -Xms32m -Xmx32m \
		-Ddw.http.port=1337 \
		-Ddw.http.adminPort=1338 \
		-jar dropwizard-helloworld/target/dropwizard-helloworld-*-SNAPSHOT.jar \
		server \
		dropwizard-helloworld/config/dev_config.yml &
elif [ "$1" == "node" ] ; then
	CONTEXTROOT=/
	node  --max-old-space-size=32 simpleserver.js &
else
	echo "ERROR: unsupported language: '$1'"
	exit 1
fi

export PID=$!
trap "echo killing process $PID... ; pkill -15 -P $PID ; kill -15 $PID ; exit" SIGHUP SIGQUIT SIGTERM

while ! nc 127.0.0.1 1337 < /dev/null > /dev/null ; do 
	echo "INFO: Waiting for server to start.."
	sleep 2
done
echo "INFO: Server started!"
rm -f logs/$1.*
ab -r -k -t 60 -n 1000000 -c 3 -g logs/$1.tsv http://127.0.0.1:1337$CONTEXTROOT >> logs/$1.log 2>&1 &
ABPID=$!
COUNT=0
BENCH_IS_RUNNING=$(ps -p $ABPID -o rss= 2>/dev/null)
while [ -n "$BENCH_IS_RUNNING" ] ; do
	MEMSIZE=$(ps -p $PID -o rss= 2>/dev/null | sed 's/ *//g')
	echo "INFO: memory size of server is now $MEMSIZE"
	echo "$(date +%s)	$MEMSIZE" >> logs/$1.memory
	sleep 1
	BENCH_IS_RUNNING=$(ps -p $ABPID -o rss= 2>/dev/null)
done
grep '^Time taken' logs/$1.log | tail -1
pkill -15 -P $PID 
kill -15 $PID
trap -  SIGHUP SIGQUIT SIGTERM

gnuplot <<!
# Let's output to a jpeg file
set terminal jpeg size 1024,500
# This sets the aspect ratio of the graph
set size 1, 1
# The file we'll write to
set output "logs/$1.jpg"
# The graph title
set title "Benchmark testing for $1 platform"
# Where to place the legend/key
set key left top
# Draw gridlines oriented on the y axis
set grid y
# Specify that the x-series data is time data
set xdata time
# Specify the *input* format of the time data
set timefmt "%s"
# Specify the *output* format for the x-axis tick labels
set format x "%S"
# Label the x-axis
set xlabel 'seconds'
# Label the y-axis
set ylabel "response time (ms)"
# Tell gnuplot to use tabs as the delimiter instead of spaces (default)
set datafile separator '\t'
# Plot the data
plot "logs/$1.tsv" every ::2 using 2:5 title 'response time' with points
exit
!
