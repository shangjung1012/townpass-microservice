<script setup>
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import TopTabs from './TopTabs.vue'
import { getConstructionData } from '@/service/api'

const router = useRouter()
const currentTab = ref('announcement')
const constructionData = ref([])
const loading = ref(false)
const error = ref('')

onMounted(async () => {
  await loadConstructionData()
})

function selectTab(tab) {
  if (tab === 'map') {
    router.push('/map')
  } else if (tab === 'recommend') {
    router.push('/')
  } else if (tab === 'announcement') {
    currentTab.value = 'announcement'
  }
}

async function loadConstructionData() {
  try {
    loading.value = true
    error.value = ''
    const data = await getConstructionData()
    // 取得施工資料並轉換為陣列
    if (data?.features) {
      constructionData.value = data.features.map((f, idx) => ({
        id: idx,
        name: f?.properties?.AP_NAME || f?.properties?.['場地名稱'] || '施工地點',
        purpose: f?.properties?.PURP || f?.properties?.['地址'] || '',
        startDate: f?.properties?.SDATE1 || '',
        endDate: f?.properties?.EDATE1 || '',
        properties: f?.properties || {}
      }))
    }
  } catch (e) {
    error.value = e?.message || String(e)
    constructionData.value = []
  } finally {
    loading.value = false
  }
}

function formatDate(dateStr) {
  if (!dateStr) return ''
  try {
    const date = new Date(dateStr)
    return date.toLocaleDateString('zh-TW')
  } catch {
    return dateStr
  }
}
</script>

<template>
  <div class="bg-white min-h-screen">
    <section class="mx-auto max-w-[720px] px-4 pt-3 pb-5">
      <TopTabs :active="currentTab" @select="selectTab" />

      <div class="mt-3">
        <div class="mb-3 flex items-center justify-between">
          <h2 class="text-lg font-semibold text-gray-800">施工公告</h2>
          <span class="text-sm text-gray-500">共 {{ constructionData.length }} 則</span>
        </div>

        <div v-if="loading" class="text-center py-12 text-gray-500">
          載入中...
        </div>

        <div v-else-if="error" class="text-center py-12 text-red-500">
          載入失敗：{{ error }}
        </div>

        <div v-else-if="constructionData.length === 0" class="text-center py-12 text-gray-500">
          目前沒有施工公告
        </div>

        <ul v-else class="space-y-3">
          <li
            v-for="item in constructionData"
            :key="item.id"
            class="rounded-lg border border-slate-200 bg-white shadow-sm p-4"
          >
            <div class="flex items-start gap-3">
              <!-- 圖示 -->
              <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-blue-900 text-white">
                <svg class="h-5 w-5" viewBox="0 0 24 24" fill="currentColor">
                  <path d="M13 3v6h8v2h-8v10h-2V11H3V9h8V3h2z"/>
                </svg>
              </div>

              <!-- 內容 -->
              <div class="flex-1">
                <h3 class="text-sm font-semibold text-gray-800">{{ item.name }}</h3>
                <p v-if="item.purpose" class="mt-1 text-xs text-gray-600">{{ item.purpose }}</p>
                
                <div v-if="item.startDate || item.endDate" class="mt-2 flex items-center gap-2 text-xs text-gray-500">
                  <svg class="h-4 w-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                    <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
                    <line x1="16" y1="2" x2="16" y2="6"></line>
                    <line x1="8" y1="2" x2="8" y2="6"></line>
                    <line x1="3" y1="10" x2="21" y2="10"></line>
                  </svg>
                  <span v-if="item.startDate">{{ formatDate(item.startDate) }}</span>
                  <span v-if="item.startDate && item.endDate">至</span>
                  <span v-if="item.endDate">{{ formatDate(item.endDate) }}</span>
                </div>
              </div>
            </div>
          </li>
        </ul>
      </div>
    </section>
  </div>
</template>

<style scoped>
</style>
