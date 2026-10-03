export default defineNitroPlugin((nitroApp) => {
  const hold = Number(process.env.READY_HOLD_MS || "0")
  const until = Date.now() + hold
  nitroApp.hooks.hook("request", () => {
    if (Date.now() < until) {
      throw createError({ statusCode: 503, statusMessage: "starting" })
    }
  })
})
