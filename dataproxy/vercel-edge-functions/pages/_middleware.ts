import type { NextRequest } from 'next/server'
import { PrismaClient } from '@prisma/client'

const prisma = new PrismaClient({})

async function getUsers() {
  // we use a transaction as it has caused issues with tracing
  // `traceparent: undefined` was being passed to the engine
  // but we ultimately want to test that queries are sent well
  const data = await prisma.$transaction([
    prisma.user.findFirst(),
    prisma.user.findMany()
  ])

  const json = JSON.stringify({ data })

  return new Response(json, {
    status: 200,
    headers: {
      "content-type": "application/json;charset=UTF-8"
    }
  })
}

export function middleware(request: NextRequest) {
  if (new URL(request.url).pathname === '/') {
    return getUsers()
  }
}
