<script setup>
import { onMounted, onBeforeUnmount, ref, createApp } from 'vue'
import mapboxgl from 'mapbox-gl'
import 'mapbox-gl/dist/mapbox-gl.css'
import MapPopup from './map/MapPopup.vue'

const mapEl = ref(null)
let map = null

// ====== Flutter 互動相關 ======
let pollTimer = null                 // 輪詢向 Flutter 要位置
let flutterMsgHandler = null         // 接收 Flutter 回覆的 handler

// Datasets
const datasets = ref([
  { id: 'accessibility', name: '無障礙據點', url: '/mapData/accessibility_new_tpe.geojson', color: '#10b981', outline: '#064e3b', visible: true },
  { id: 'attraction', name: '景點', url: '/mapData/attraction_tpe.geojson', color: '#f59e0b', outline: '#92400e', visible: false },
])

const datasetCache = new Map()

function computeBounds(geo) {
  const bounds = new mapboxgl.LngLatBounds()
  for (const f of geo.features || []) {
    const g = f.geometry
    if (!g) continue
    if (g.type === 'Point') bounds.extend(g.coordinates)
    else if (g.type === 'MultiPoint' || g.type === 'LineString') for (const c of g.coordinates) bounds.extend(c)
    else if (g.type === 'MultiLineString' || g.type === 'Polygon') for (const ring of g.coordinates) for (const c of ring) bounds.extend(c)
    else if (g.type === 'MultiPolygon') for (const poly of g.coordinates) for (const ring of poly) for (const c of ring) bounds.extend(c)
  }
  return bounds
}

function attachPopupInteraction(layerId) {
  map.on('mouseenter', layerId, () => { map.getCanvas().style.cursor = 'pointer' })
  map.on('mouseleave', layerId, () => { map.getCanvas().style.cursor = '' })
  map.on('click', layerId, (e) => {
    const feature = e?.features?.[0]
    if (!feature) return
    const props = feature.properties || {}
    const container = document.createElement('div')
    const app = createApp(MapPopup, { properties: props })
    app.mount(container)
    const popup = new mapboxgl.Popup({ offset: 8 })
      .setLngLat(e.lngLat)
      .setDOMContent(container)
      .addTo(map)
    popup.on('close', () => app.unmount())
  })
}

async function ensureDatasetLoaded(ds) {
  if (!map || datasetCache.has(ds.id)) return
  const geo = await fetch(ds.url).then(r => r.json())
  const sourceId = `geo-${ds.id}`
  const first = geo?.features?.[0]
  const geomType = first?.geometry?.type || ''
  map.addSource(sourceId, { type: 'geojson', data: geo })
  const layerIds = []
  if (geomType.includes('Point')) {
    const lid = `${ds.id}-points`
    map.addLayer({
      id: lid,
      type: 'circle',
      source: sourceId,
      paint: {
        'circle-radius': 6,
        'circle-color': ds.color,
        'circle-stroke-width': 1,
        'circle-stroke-color': ds.outline
      },
      layout: { visibility: ds.visible ? 'visible' : 'none' }
    })
    layerIds.push(lid)
    attachPopupInteraction(lid)
  } else if (geomType.includes('Line')) {
    const lid = `${ds.id}-lines`
    map.addLayer({
      id: lid,
      type: 'line',
      source: sourceId,
      paint: { 'line-color': ds.color, 'line-width': 2 },
      layout: { visibility: ds.visible ? 'visible' : 'none' }
    })
    layerIds.push(lid)
    attachPopupInteraction(lid)
  } else {
    const fillId = `${ds.id}-fill`
    const outlineId = `${ds.id}-outline`
    map.addLayer({
      id: fillId,
      type: 'fill',
      source: sourceId,
      paint: { 'fill-color': ds.color, 'fill-opacity': 0.2 },
      layout: { visibility: ds.visible ? 'visible' : 'none' }
    })
    map.addLayer({
      id: outlineId,
      type: 'line',
      source: sourceId,
      paint: { 'line-color': ds.outline, 'line-width': 1 },
      layout: { visibility: ds.visible ? 'visible' : 'none' }
    })
    layerIds.push(fillId, outlineId)
    attachPopupInteraction(fillId)
  }
  datasetCache.set(ds.id, { sourceId, layerIds, geo, bounds: computeBounds(geo) })
}

function setDatasetVisibility(ds, visible) {
  const cache = datasetCache.get(ds.id)
  if (!cache) return
  for (const lid of cache.layerIds) if (map.getLayer(lid)) map.setLayoutProperty(lid, 'visibility', visible ? 'visible' : 'none')
}

function fitToVisibleDatasets() {
  const visible = datasets.value.map(d => d.visible ? datasetCache.get(d.id) : null).filter(Boolean)
  if (visible.length === 0) return
  const combined = new mapboxgl.LngLatBounds()
  for (const c of visible) if (c.bounds && !c.bounds.isEmpty()) {
    combined.extend(c.bounds.getSouthWest())
    combined.extend(c.bounds.getNorthEast())
  }
  if (!combined.isEmpty()) map.fitBounds(combined, { padding: 40, duration: 500 })
}

// ===== 使用者定位（只吃 Flutter 提供）=====
function ensureUserLayer() {
  if (!map.getSource('user-location')) {
    map.addSource('user-location', {
      type: 'geojson',
      data: { type: 'FeatureCollection', features: [] }
    })
  }
  if (!map.getLayer('user-location-circle')) {
    map.addLayer({
      id: 'user-location-circle',
      type: 'circle',
      source: 'user-location',
      paint: {
        'circle-radius': 8,
        'circle-color': '#2563eb',
        'circle-stroke-width': 2,
        'circle-stroke-color': '#ffffff'
      }
    })
  }
}

function updateUserLocation(lon, lat) {
  const src = map.getSource('user-location')
  if (!src) return
  const geo = {
    type: 'FeatureCollection',
    features: [{ type: 'Feature', geometry: { type: 'Point', coordinates: [lon, lat] } }]
  }
  src.setData(geo)
  map.flyTo({ center: [lon, lat], zoom: 15 })
}

function handleIncomingMessage(raw) {
  try {
    const msg = typeof raw === 'string' ? JSON.parse(raw) : raw
    const payload = msg?.data ?? msg
    const name = msg?.name ?? null
    if (name === 'location' && payload) {
      const lat = payload.latitude ?? payload.lat ?? payload.coords?.latitude
      const lon = payload.longitude ?? payload.lng ?? payload.lon ?? payload.coords?.longitude
      if (typeof lat === 'number' && typeof lon === 'number') {
        updateUserLocation(lon, lat)
      }
    }
  } catch (err) {
    console.warn('Invalid location message', err)
  }
}

// 定期向 Flutter 要位置（TownPass 已有 handler：name='location'）
function requestLocationFromFlutter() {
  try {
    const payload = JSON.stringify({ name: 'location' })
    if (window.flutterObject?.postMessage) {
      window.flutterObject.postMessage(payload)
      return true
    }
  } catch (_) {}
  return false
}

function startPollingFlutter(intervalMs = 2000) {
  // 先要一次
  requestLocationFromFlutter()
  // 之後定期要
  pollTimer = setInterval(requestLocationFromFlutter, intervalMs)
}

onMounted(() => {
  const token = import.meta.env.VITE_MAPBOXTOKEN
  const styleUrl = 'mapbox://styles/mapbox/streets-v12'
  if (!token) {
    console.warn('VITE_MAPBOXTOKEN is missing')
    return
  }
  mapboxgl.accessToken = token

  map = new mapboxgl.Map({
    container: mapEl.value,
    style: styleUrl,
    center: [121.5654, 25.0330],
    zoom: 11
  })

  map.addControl(new mapboxgl.NavigationControl())

  map.on('load', async () => {
    for (const ds of datasets.value) await ensureDatasetLoaded(ds)
    fitToVisibleDatasets()
    ensureUserLayer()

    // 註冊接收（盡量相容）
    window.receiveLocationFromFlutter = (msg) => handleIncomingMessage(msg)
    if (window.flutterObject && typeof window.flutterObject.addEventListener === 'function') {
      flutterMsgHandler = (e) => handleIncomingMessage(e?.data ?? e)
      try { window.flutterObject.addEventListener('message', flutterMsgHandler) } catch (_) {}
    } else {
      flutterMsgHandler = (e) => handleIncomingMessage(e?.data ?? e)
      window.addEventListener('message', flutterMsgHandler)
    }

    // 僅用 Flutter 提供位置：啟動輪詢要求
    startPollingFlutter(2000)
  })
})

onBeforeUnmount(() => {
  if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
  if (flutterMsgHandler) {
    if (window.flutterObject && typeof window.flutterObject.removeEventListener === 'function') {
      try { window.flutterObject.removeEventListener('message', flutterMsgHandler) } catch (_) {}
    } else {
      window.removeEventListener('message', flutterMsgHandler)
    }
  }
  try { delete window.receiveLocationFromFlutter } catch (_) {}
  if (map) map.remove()
})
</script>

<template>
  <section class="h-full flex flex-col">
    <div class="flex items-center gap-3 py-2">
      <h1 class="text-2xl font-semibold">地圖</h1>
      <div class="flex items-center gap-3 flex-wrap">
        <label v-for="ds in datasets" :key="ds.id" class="inline-flex items-center gap-2 text-sm">
          <input type="checkbox" v-model="ds.visible"
                 @change="() => { setDatasetVisibility(ds, ds.visible); fitToVisibleDatasets() }" />
          <span>{{ ds.name }}</span>
        </label>
      </div>
    </div>
    <div ref="mapEl" class="flex-1 min-h-[400px]" />
  </section>
</template>

<style scoped>
</style>
