export default defineEventHandler((event) => {
  const path = event.path || "/"
  if (path === "/healthz" || path === "/readyz") {
    return
  }
  if (process.env.SITE_OPEN !== "yes") {
    throw createError({ statusCode: 403, statusMessage: "closed" })
  }
})
