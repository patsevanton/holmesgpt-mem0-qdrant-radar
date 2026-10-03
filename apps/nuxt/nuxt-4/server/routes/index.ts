const stash: Buffer[] = []

export default defineEventHandler(() => {
  stash.push(Buffer.alloc(8 * 1024 * 1024, 1))
  return "ok"
})
