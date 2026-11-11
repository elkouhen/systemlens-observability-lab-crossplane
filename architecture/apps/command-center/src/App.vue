<script setup>
import { computed, ref } from 'vue'

const commands = [
  {
    id: 'architecture-status',
    label: 'Architecture',
    description: "Afficher la configuration de l'architecture",
    command: 'make architecture-status',
    icon: '⌘',
    tone: 'violet',
  },
  {
    id: 'kubernetes-status',
    label: 'Kubernetes',
    description: "Vérifier l'état des services",
    command: 'make kubernetes-status',
    icon: '◈',
    tone: 'blue',
  },
  {
    id: 'stock-show',
    label: 'Stock',
    description: 'Afficher le catalogue disponible',
    command: 'make stock-show',
    icon: '▦',
    tone: 'orange',
  },
]

const output = ref([
  '$ Command Center prêt',
  'Sélectionnez une commande pour afficher son résultat.',
])
const selectedCommand = ref('architecture-status')
const productId = ref('PASTA-500G')
const quantity = ref(1)
const isRunning = ref(false)
const lastRun = ref('À l’instant')
const history = ref([])

const selected = computed(() => commands.find(({ id }) => id === selectedCommand.value))

function runCommand(command = selectedCommand.value) {
  const item = commands.find(({ id }) => id === command)
  if (!item || isRunning.value) return

  selectedCommand.value = command
  isRunning.value = true
  output.value = [`$ ${item.command}`, '', 'Exécution en cours…']

  window.setTimeout(() => {
    const result = commandResult(command)
    output.value = [`$ ${item.command}`, '', ...result]
    history.value.unshift({ label: item.label, command: item.command, time: 'maintenant' })
    history.value = history.value.slice(0, 4)
    lastRun.value = 'À l’instant'
    isRunning.value = false
  }, 450)
}

function sendOrder() {
  if (!productId.value.trim() || quantity.value < 1 || isRunning.value) return

  isRunning.value = true
  const command = `POST /api/orders  { productId: "${productId.value.trim()}", quantity: ${quantity.value} }`
  output.value = [`$ ${command}`, '', 'Envoi de la commande…']

  window.setTimeout(() => {
    const orderId = `ORD-${Math.floor(1000 + Math.random() * 9000)}`
    output.value = [
      `$ ${command}`,
      '',
      '✓ Commande acceptée',
      `  orderId : ${orderId}`,
      `  produit : ${productId.value.trim()}`,
      `  quantité : ${quantity.value}`,
      '  statut  : CREATED',
    ]
    history.value.unshift({ label: 'Nouvelle commande', command, time: 'maintenant' })
    history.value = history.value.slice(0, 4)
    lastRun.value = 'À l’instant'
    isRunning.value = false
  }, 600)
}

function commandResult(command) {
  if (command === 'architecture-status') {
    return ['✓ ARCH_NAME=Hybride Fleet', '  ELASTIC_STACK_VERSION=9.5.4', '  ARCH_ROOT=.']
  }
  if (command === 'kubernetes-status') {
    return ['✓ elastic-stack   Elasticsearch, Kibana, Fleet   READY', '✓ h0tl-supermarche-app   3 services   READY']
  }
  return ['✓ Catalogue PostgreSQL', '  12 produits disponibles', '  4 produits avec stock faible']
}
</script>

<template>
  <div class="shell">
    <header class="topbar">
      <div class="brand">
        <div class="brand-mark"><span></span><span></span><span></span></div>
        <div>
          <p class="eyebrow">SYSTEMLENS / OPERATIONS</p>
          <h1>Command Center</h1>
        </div>
      </div>
      <div class="connection"><span class="pulse"></span> Mode démonstration <span class="slash">/</span> local</div>
    </header>

    <main>
      <section class="hero">
        <div>
          <p class="eyebrow accent">CONSOLE OPÉRATIONNELLE</p>
          <h2>Les commandes utiles,<br /><em>à portée de main.</em></h2>
          <p class="hero-copy">Lancez les contrôles fréquents de la plateforme et suivez leur résultat depuis un seul écran.</p>
        </div>
        <div class="hero-orbit" aria-hidden="true"><span></span><span></span><span></span></div>
      </section>

      <section class="section-heading">
        <div><p class="eyebrow">01 / ACTIONS RAPIDES</p><h3>Commandes fréquentes</h3></div>
        <span class="count">{{ commands.length }} disponibles</span>
      </section>

      <section class="command-grid">
        <button v-for="item in commands" :key="item.id" class="command-card" :class="[{ active: selectedCommand === item.id }, item.tone]" @click="runCommand(item.id)">
          <div class="card-top"><span class="command-icon">{{ item.icon }}</span><span class="run-icon">↗</span></div>
          <div class="card-content"><h4>{{ item.label }}</h4><p>{{ item.description }}</p></div>
          <code>{{ item.command }}</code>
        </button>
      </section>

      <section class="workspace">
        <div class="terminal-panel panel">
          <div class="panel-heading"><div><p class="eyebrow">02 / SORTIE</p><h3>Résultat de la commande</h3></div><span class="status-tag" :class="{ running: isRunning }"><i></i>{{ isRunning ? 'En cours' : 'Prêt' }}</span></div>
          <div class="terminal" aria-live="polite"><p v-for="(line, index) in output" :key="`${line}-${index}`" :class="{ muted: index === 1 && !isRunning, success: line.includes('✓') }">{{ line || ' ' }}</p><span v-if="isRunning" class="cursor"></span></div>
          <div class="terminal-footer"><span>Dernière exécution : {{ lastRun }}</span><button @click="runCommand()" :disabled="isRunning">{{ isRunning ? 'Exécution...' : 'Relancer' }} <span>↗</span></button></div>
        </div>

        <div class="order-panel panel">
          <div class="panel-heading"><div><p class="eyebrow">03 / MÉTIER</p><h3>Envoyer une commande</h3></div><span class="order-badge">REST</span></div>
          <form @submit.prevent="sendOrder">
            <label for="product">Identifiant produit</label>
            <input id="product" v-model="productId" placeholder="PASTA-500G" autocomplete="off" />
            <label for="quantity">Quantité</label>
            <div class="quantity-field"><button type="button" @click="quantity = Math.max(1, quantity - 1)">−</button><input id="quantity" v-model.number="quantity" type="number" min="1" /><button type="button" @click="quantity += 1">+</button></div>
            <button class="primary-button" type="submit" :disabled="isRunning || !productId.trim()">Envoyer la commande <span>↗</span></button>
          </form>
          <p class="form-note"><span>i</span> La commande est simulée dans ce mode local.</p>
        </div>
      </section>

      <section class="history-section">
        <div class="section-heading"><div><p class="eyebrow">04 / JOURNAL</p><h3>Activité récente</h3></div><span class="count">{{ history.length }} exécutions</span></div>
        <div v-if="history.length" class="history-list"><div v-for="entry in history" :key="`${entry.command}-${entry.time}`" class="history-row"><span class="history-dot"></span><strong>{{ entry.label }}</strong><code>{{ entry.command }}</code><time>{{ entry.time }}</time></div></div>
        <div v-else class="empty-history">Les commandes lancées apparaîtront ici.</div>
      </section>
    </main>
    <footer><span>COMMAND CENTER</span><span>Vue.js · interface locale</span></footer>
  </div>
</template>
