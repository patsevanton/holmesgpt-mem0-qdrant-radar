package main

import (
	"fmt"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprint(w, "ok")
	})
	addr := os.Getenv("LISTEN_ADDR")
	if addr == "" {
		addr = ":8080"
	}
	if os.Getenv("REQUIRE_TOKEN") == "true" {
		token := os.Getenv("APP_TOKEN")
		if token == "" {
			fmt.Fprintln(os.Stderr, "APP_TOKEN is empty")
			os.Exit(1)
		}
	}
	if err := http.ListenAndServe(addr, nil); err != nil {
		panic(err)
	}
}
