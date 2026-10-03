export default defineEventHandler((event) => {
  const expected = process.env.BIND_HOST || "0.0.0.0"
  const host = getRequestHost(event, { xForwardedHost: false })
  if (host !== expected && !host.startsWith(expected + ":")) {
    setResponseStatus(event, 421)
    return "mismatch"
  }
  return "ok"
})
