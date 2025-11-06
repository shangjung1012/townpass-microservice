<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import TopTabs from './TopTabs.vue'
import { hello, echo, listUsers, createUser, listTestRecords, createTestRecord } from '@/service/api'

const hi = ref(null)          // GET /api/hello 回傳
const echoMsg = ref('ping')   // POST /api/echo 輸入
const echoResp = ref(null)    // POST /api/echo 回傳

const users = ref([])         // GET /api/users 回傳
const newName = ref('Alice')  // POST /api/users 的 name

const tests = ref([])         // GET /api/test_records 回傳
const newTestTitle = ref('Sample title')
const newTestDescription = ref('A short description')

const loading = ref(false)
const error = ref('')
const router = useRouter()
const currentTab = ref('recommend')
const savedPlaces = ref([])
const expandedFavoriteIds = ref([])
const FAVORITES_STORAGE_KEY = 'mapFavorites'

onMounted(async () => {
  try {
    loading.value = true
    error.value = ''
    hi.value = await hello()
    users.value = await listUsers()
    tests.value = await listTestRecords()
  } catch (e) {
    error.value = e?.message || String(e)
  } finally {
    loading.value = false
  }
  loadSavedPlaces()
  if (typeof window !== 'undefined') {
    window.addEventListener('map-favorites-updated', loadSavedPlaces)
  }
})

onBeforeUnmount(() => {
  if (typeof window !== 'undefined') {
    window.removeEventListener('map-favorites-updated', loadSavedPlaces)
  }
})

async function sendEcho() {
  try {
    loading.value = true
    error.value = ''
    echoResp.value = await echo(echoMsg.value)
  } catch (e) {
    error.value = e?.message || String(e)
  } finally {
    loading.value = false
  }
}

async function addUser() {
  try {
    loading.value = true
    error.value = ''
    await createUser({ name: newName.value })
    users.value = await listUsers()   // 重新抓清單
    newName.value = ''
  } catch (e) {
    error.value = e?.message || String(e)
  } finally {
    loading.value = false
  }
}

async function addTestRecord() {
  try {
    loading.value = true
    error.value = ''
    await createTestRecord({ title: newTestTitle.value, description: newTestDescription.value })
    tests.value = await listTestRecords()
    newTestTitle.value = ''
    newTestDescription.value = ''
  } catch (e) {
    error.value = e?.message || String(e)
  } finally {
    loading.value = false
  }
}

function selectTab(tab) {
  if (tab === 'recommend') {
    currentTab.value = 'recommend'
    if (router.currentRoute.value.path !== '/') {
      router.push('/')
    }
    return
  }

  currentTab.value = 'map'
  if (router.currentRoute.value.path !== '/map') {
    router.push('/map')
  }
}

function readSavedPlaces() {
  if (typeof window === 'undefined') return []
  try {
    const raw = localStorage.getItem(FAVORITES_STORAGE_KEY)
    if (!raw) return []
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch (_) {
    return []
  }
}

function loadSavedPlaces() {
  const list = readSavedPlaces().map((item) => ({
    ...item,
    recommendations: Array.isArray(item?.recommendations) ? item.recommendations : [],
  }))
  list.sort((a, b) => {
    const da = a?.addedAt ? Date.parse(a.addedAt) : 0
    const db = b?.addedAt ? Date.parse(b.addedAt) : 0
    return db - da
  })
  savedPlaces.value = list
  expandedFavoriteIds.value = expandedFavoriteIds.value.filter((id) => list.some((place) => place.id === id))
}

function saveFavorites(list) {
  if (typeof window === 'undefined') return
  localStorage.setItem(FAVORITES_STORAGE_KEY, JSON.stringify(list))
  window.dispatchEvent(new CustomEvent('map-favorites-updated'))
}

function isFavoriteExpanded(id) {
  return expandedFavoriteIds.value.includes(id)
}

function toggleFavoriteDetails(id) {
  if (isFavoriteExpanded(id)) {
    expandedFavoriteIds.value = expandedFavoriteIds.value.filter((item) => item !== id)
  } else {
    expandedFavoriteIds.value = [...expandedFavoriteIds.value, id]
  }
}

function removeFavorite(id) {
  const next = savedPlaces.value.filter((place) => place.id !== id)
  savedPlaces.value = next
  expandedFavoriteIds.value = expandedFavoriteIds.value.filter((item) => item !== id)
  saveFavorites(next)
}

function formatFavoriteDate(value) {
  if (!value) return ''
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) return ''
  try {
    return date.toLocaleString('zh-TW', { hour12: false })
  } catch (_) {
    return date.toLocaleString()
  }
}

function formatDistance(meters) {
  if (typeof meters !== 'number' || Number.isNaN(meters)) return ''
  if (meters >= 1000) {
    const km = meters / 1000
    return `${km >= 10 ? km.toFixed(0) : km.toFixed(1)} 公里`
  }
  return `${Math.round(meters)} 公尺`
}
</script>

<template>
  <section class="mx-auto max-w-[720px] px-4 pt-3 pb-5">
    <TopTabs :active="currentTab" @select="selectTab" />

    <div v-if="currentTab === 'recommend'" class="grid gap-4 mt-3">
      <article class="border border-blue-100 rounded-lg bg-blue-50/60 shadow-sm">
        <header class="flex items-center justify-between px-4 py-3">
          <h2 class="text-sm font-semibold text-gray-800">收藏地點</h2>
          <span class="text-xs text-gray-500">共 {{ savedPlaces.length }} 筆</span>
        </header>
        <div class="border-t border-blue-100 bg-white/70 px-4 py-3">
          <p v-if="savedPlaces.length === 0" class="text-sm text-gray-500">目前尚未收藏地點。</p>
          <ul v-else class="space-y-3">
            <li
              v-for="place in savedPlaces"
              :key="place.id"
              class="rounded-lg border border-slate-100 bg-white shadow-sm"
            >
              <button
                type="button"
                class="flex w-full items-start justify-between gap-3 px-3 py-3 text-left"
                @click="toggleFavoriteDetails(place.id)"
              >
                <div class="flex-1">
                  <div class="text-sm font-semibold text-gray-800">{{ place.name }}</div>
                  <div v-if="place.address" class="mt-0.5 text-xs text-gray-500">{{ place.address }}</div>
                  <div v-else-if="place.addr" class="mt-0.5 text-xs text-gray-500">{{ place.addr }}</div>
                  <div v-if="place.addedAt" class="mt-1 text-[11px] text-gray-400">收藏時間 {{ formatFavoriteDate(place.addedAt) }}</div>
                </div>
                <span
                  class="mt-1 inline-block text-sm text-blue-500 transition-transform"
                  :class="isFavoriteExpanded(place.id) ? 'rotate-180' : 'rotate-0'"
                >▼</span>
              </button>
              <div class="flex items-center justify-between border-t border-slate-100 px-3 py-2">
                <span class="text-[11px] text-gray-500">附近推薦 {{ place.recommendations.length }} 筆</span>
                <button
                  type="button"
                  class="text-xs text-red-500 hover:underline"
                  @click.stop="removeFavorite(place.id)"
                >取消收藏</button>
              </div>
              <div
                v-if="isFavoriteExpanded(place.id)"
                class="space-y-3 border-t border-slate-100 bg-slate-50 px-3 py-3 text-sm"
              >
                <template v-if="place.recommendations.length">
                  <div
                    v-for="rec in place.recommendations"
                    :key="rec.id || rec.name"
                    class="rounded-md border border-slate-200 bg-white/90 px-3 py-2 text-xs text-gray-700"
                  >
                    <div class="font-medium text-gray-800">{{ rec.name }}</div>
                    <div v-if="rec.addr" class="text-[11px] text-gray-500">{{ rec.addr }}</div>
                    <div v-if="typeof rec.dist === 'number'" class="text-[11px] text-gray-400">距離約 {{ formatDistance(rec.dist) }}</div>
                  </div>
                </template>
                <p v-else class="text-xs text-gray-500">暫無附近推薦資訊。</p>
              </div>
            </li>
          </ul>
        </div>
      </article>

      <h1 class="text-3xl font-bold">Home</h1>

      <div v-if="loading" class="text-gray-500">Loading…</div>
      <div v-if="error" class="text-red-600">Error: {{ error }}</div>

      <!-- 1) 測試 GET /api/hello -->
      <article class="border border-gray-200 rounded-lg p-3">
        <h3 class="font-semibold mb-2">GET /api/hello</h3>
        <pre class="bg-gray-100 p-2 rounded overflow-auto">{{ hi }}</pre>
      </article>

      <!-- 2) 測試 POST /api/echo（用來驗證 CORS） -->
      <article class="border border-gray-200 rounded-lg p-3">
        <h3 class="font-semibold mb-2">POST /api/echo</h3>
        <div class="flex items-center gap-2">
          <input v-model="echoMsg" placeholder="type a message" class="px-2 py-1 border border-gray-300 rounded" />
          <button @click="sendEcho" class="px-3 py-1 border border-gray-400 rounded hover:border-indigo-500">Send</button>
        </div>
        <pre class="bg-gray-100 p-2 rounded mt-2 overflow-auto">{{ echoResp }}</pre>
      </article>

      <!-- 3) 測試 /api/users 清單 + 建立 -->
      <article class="border border-gray-200 rounded-lg p-3">
        <h3 class="font-semibold mb-2">Users</h3>
        <div class="flex items-center gap-2">
          <input v-model="newName" placeholder="name" class="px-2 py-1 border border-gray-300 rounded" />
          <button @click="addUser" class="px-3 py-1 border border-gray-400 rounded hover:border-indigo-500">Add</button>
        </div>
        <ul class="mt-2 list-disc pl-6">
          <li v-for="u in users" :key="u.id">{{ u.id }} — {{ u.name }}</li>
        </ul>
      </article>

      <!-- 4) 測試 /api/test_records 清單 + 建立 -->
      <article class="border border-gray-200 rounded-lg p-3">
        <h3 class="font-semibold mb-2">Test Records</h3>
        <div class="flex items-center flex-wrap gap-2">
          <input v-model="newTestTitle" placeholder="title" class="flex-1 min-w-[200px] px-2 py-1 border border-gray-300 rounded" />
          <input v-model="newTestDescription" placeholder="description" class="flex-[2] min-w-[200px] px-2 py-1 border border-gray-300 rounded" />
          <button @click="addTestRecord" class="px-3 py-1 border border-gray-400 rounded hover:border-indigo-500">Add Test</button>
        </div>
        <ul class="mt-2 list-disc pl-6">
          <li v-for="t in tests" :key="t.id">{{ t.id }} — <strong>{{ t.title }}</strong> — {{ t.description }}</li>
        </ul>
      </article>
    </div>
  </section>
</template>

<style scoped>
</style>
