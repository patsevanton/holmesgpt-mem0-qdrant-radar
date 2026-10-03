package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "ok")
	})
	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	delay := os.Getenv("START_DELAY")
	if delay == "" {
		delay = "2s"
	}
	d, err := time.ParseDuration(delay)
	if err != nil {
		panic(err)
	}
	time.Sleep(d)
	if err := http.ListenAndServe(addr, nil); err != nil {
		panic(err)
	}
}
