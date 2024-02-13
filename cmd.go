package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"syscall"
	"time"
)

const (
	PortInUse = "inuse"
	PortFree  = "free"
)
