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
	go func() {
		time.Sleep(20 * time.Second)
		os.Exit(1)
	}()
	if err := http.ListenAndServe(addr, nil); err != nil {
		panic(err)
	}
}
