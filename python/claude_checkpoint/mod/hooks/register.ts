async function lookup($, id) {
  const r = await $.mcp.call('temporal', 'lookup', { id })
  return JSON.parse(r.content[0].text)
}

async function checkpoint($, id, value) {
  await $.mcp.call('temporal', 'checkpoint', { id, value })
}

export function register(on) {
  on('tool.call', async ($, e, next) => {
    if (e.tool.startsWith('mcp__temporal__')) {
      return next.origin.plugin === 'engine' ? { deny: `${e.tool} is internal` } : next(e)
    }
    const id = `tool-${e.tool_use_id}`
    const saved = await lookup($, id)
    if (saved !== null) return { result: saved }
    const r = await next(e)
    if (r.deny === undefined) await checkpoint($, id, r.result)
    return r
  }).catch(($, e, next) => ({ deny: `checkpoint failed: ${next.error.message}` }))

  on('turn.step', async function* ($, e, next) {
    const id = `model-${e.agentId ?? 'main'}-${await $.session.turns()}-${e.index}`
    const saved = await lookup($, id)
    if (saved !== null) {
      for (const chunk of saved.chunks) yield chunk
      return { ...saved.result, turnId: e.turnId, index: e.index }
    }
    const chunks = []
    const stream = next(e)
    for await (const chunk of stream) {
      if (chunk.kind !== 'engine') {
        const { ref, ...data } = chunk
        chunks.push(data)
      }
      yield chunk
    }
    const result = await stream.result
    await checkpoint($, id, { chunks, result })
    return result
  })
}
