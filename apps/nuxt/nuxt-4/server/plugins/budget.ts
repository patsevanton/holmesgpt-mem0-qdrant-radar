const cap = Number(process.env.HEAP_CAP_MB || "256") * 1024 * 1024

setInterval(() => {
  const used = process.memoryUsage().heapUsed
  if (used > cap) {
    process.exit(137)
  }
}, 500)
