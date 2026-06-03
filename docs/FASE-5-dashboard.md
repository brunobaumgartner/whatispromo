# WhatPromo — Fase 5: Dashboard Analítico

## Objetivo
Visualizações de dados sobre performance das ofertas, receita estimada de
afiliados e comportamento dos grupos. Base para decisões de negócio.

## Pré-requisitos
- Fase 4 concluída (painel admin funcionando)
- Pelo menos 2 semanas de dados coletados para os gráficos fazerem sentido

---

## Métricas do dashboard

| Métrica | Como calcular | Para que serve |
|---|---|---|
| Ofertas por dia | COUNT por DATE(raspado_em) | Ver volume de coleta |
| Taxa de aprovação | aprovadas / total * 100 | Avaliar qualidade das lojas |
| Principais motivos de rejeição | GROUP BY motivo_rejeicao | Ajustar thresholds |
| CTR por categoria | cliques / disparos * 100 | Saber qual nicho converte mais |
| Score médio aprovadas vs rejeitadas | AVG(pontuacao_ia) por status | Calibrar score mínimo |
| Receita estimada | cliques * ticket_medio * taxa_conversao | Projeção de ganhos com afiliados |
| Grupos mais ativos | COUNT disparos por grupo | Saber onde focar |
| Horários de melhor CTR | cliques por hora do dia | Otimizar janela de envio |

---

## Etapa 1 — Queries SQL das métricas

Crie `/srv/whatpromo/painel/app/Services/ServicoDashboard.php`:

```php
<?php
// WhatPromo — Serviço de métricas do dashboard
// Todas as queries de agregação ficam aqui.
// Os resultados são cacheados por 5 minutos para não sobrecarregar o banco.

namespace App\Services;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Cache;

class ServicoDashboard
{
    // TTL do cache em segundos (5 minutos)
    private const CACHE_TTL = 300;

    public function obter_resumo_periodo(int $dias = 7): array
    {
        return Cache::remember("dashboard_resumo_{$dias}d", self::CACHE_TTL, function () use ($dias) {
            return DB::select("
                SELECT
                    COUNT(*)                                    as total_coletadas,
                    SUM(status = 'enviada')                     as total_enviadas,
                    SUM(status = 'rejeitada')                   as total_rejeitadas,
                    ROUND(AVG(pontuacao_ia), 1)                 as score_medio,
                    ROUND(SUM(status='enviada')/COUNT(*)*100,1) as taxa_aprovacao
                FROM ofertas
                WHERE raspado_em >= DATE_SUB(NOW(), INTERVAL :dias DAY)
            ", ['dias' => $dias])[0];
        });
    }

    public function obter_ofertas_por_dia(int $dias = 30): array
    {
        return Cache::remember("dashboard_por_dia_{$dias}d", self::CACHE_TTL, function () use ($dias) {
            return DB::select("
                SELECT
                    DATE(raspado_em) as data,
                    COUNT(*)         as coletadas,
                    SUM(status = 'enviada') as enviadas
                FROM ofertas
                WHERE raspado_em >= DATE_SUB(NOW(), INTERVAL :dias DAY)
                GROUP BY DATE(raspado_em)
                ORDER BY data ASC
            ", ['dias' => $dias]);
        });
    }

    public function obter_rejeicoes_por_motivo(int $dias = 7): array
    {
        return Cache::remember("dashboard_rejeicoes_{$dias}d", self::CACHE_TTL, function () use ($dias) {
            return DB::select("
                SELECT motivo_rejeicao, COUNT(*) as total
                FROM ofertas
                WHERE status = 'rejeitada'
                  AND raspado_em >= DATE_SUB(NOW(), INTERVAL :dias DAY)
                  AND motivo_rejeicao IS NOT NULL
                GROUP BY motivo_rejeicao
                ORDER BY total DESC
            ", ['dias' => $dias]);
        });
    }

    public function obter_ctr_por_categoria(int $dias = 30): array
    {
        return Cache::remember("dashboard_ctr_{$dias}d", self::CACHE_TTL, function () use ($dias) {
            return DB::select("
                SELECT
                    o.categoria,
                    COUNT(d.id)      as disparos,
                    SUM(d.cliques)   as cliques,
                    ROUND(SUM(d.cliques) / NULLIF(COUNT(d.id), 0) * 100, 1) as ctr
                FROM disparos d
                JOIN ofertas o ON d.oferta_id = o.id
                WHERE d.disparado_em >= DATE_SUB(NOW(), INTERVAL :dias DAY)
                GROUP BY o.categoria
                ORDER BY ctr DESC
            ", ['dias' => $dias]);
        });
    }

    public function obter_receita_estimada(int $dias = 30): array
    {
        // Taxa de conversão estimada: 2% (conservador para grupos de ofertas)
        // Ticket médio estimado: R$ 150 (média entre as categorias)
        // Comissão média estimada: 8% (média ML + Shopee)
        $taxa_conversao = 0.02;
        $ticket_medio   = 150.00;
        $comissao_media = 0.08;

        return Cache::remember("dashboard_receita_{$dias}d", self::CACHE_TTL, function ()
            use ($dias, $taxa_conversao, $ticket_medio, $comissao_media) {
            $resultado = DB::select("
                SELECT SUM(cliques) as total_cliques
                FROM disparos
                WHERE disparado_em >= DATE_SUB(NOW(), INTERVAL :dias DAY)
                  AND status = 'sucesso'
            ", ['dias' => $dias])[0];

            $cliques  = $resultado->total_cliques ?? 0;
            $vendas   = $cliques * $taxa_conversao;
            $receita  = $vendas * $ticket_medio * $comissao_media;

            return [
                'total_cliques'   => $cliques,
                'vendas_estimadas' => round($vendas),
                'receita_estimada' => round($receita, 2),
            ];
        });
    }
}
```

---

## Etapa 2 — Controller do dashboard

Crie `/srv/whatpromo/painel/app/Http/Controllers/DashboardController.php`:

```php
<?php
namespace App\Http\Controllers;

use App\Services\ServicoDashboard;
use Illuminate\Http\Request;
use Inertia\Inertia;

class DashboardController extends Controller
{
    public function index(Request $request, ServicoDashboard $servico)
    {
        // Período selecionado pelo usuário (padrão: 7 dias)
        $dias = (int) $request->get('dias', 7);
        $dias = in_array($dias, [7, 30, 90]) ? $dias : 7;

        return Inertia::render('Dashboard/Index', [
            'resumo'            => $servico->obter_resumo_periodo($dias),
            'ofertas_por_dia'   => $servico->obter_ofertas_por_dia($dias),
            'rejeicoes'         => $servico->obter_rejeicoes_por_motivo($dias),
            'ctr_por_categoria' => $servico->obter_ctr_por_categoria($dias),
            'receita'           => $servico->obter_receita_estimada($dias),
            'periodo_dias'      => $dias,
        ]);
    }
}
```

---

## Etapa 3 — Rota do dashboard

Adicionar em `routes/web.php`:

```php
Route::get('/dashboard', [DashboardController::class, 'index'])->name('dashboard')->middleware('auth');
```

---

## Etapa 4 — Componente Vue do dashboard

Crie `/srv/whatpromo/painel/resources/js/Pages/Dashboard/Index.vue`:

```vue
<script setup>
// WhatPromo — Tela principal do dashboard analítico
// Usa Chart.js para os gráficos (já incluso no Laravel Breeze)

import { ref } from 'vue'
import { router } from '@inertiajs/vue3'

const props = defineProps({
  resumo:            Object,
  ofertas_por_dia:   Array,
  rejeicoes:         Array,
  ctr_por_categoria: Array,
  receita:           Object,
  periodo_dias:      Number,
})

// Altera o período e recarrega a página com os novos dados
function alterarPeriodo(dias) {
  router.get('/dashboard', { dias }, { preserveState: true })
}
</script>

<template>
  <div class="p-6">
    <h1 class="text-2xl font-bold mb-6">Dashboard</h1>

    <!-- Seletor de período -->
    <div class="flex gap-2 mb-6">
      <button
        v-for="dias in [7, 30, 90]"
        :key="dias"
        @click="alterarPeriodo(dias)"
        :class="periodo_dias === dias ? 'bg-green-600 text-white' : 'bg-gray-100'"
        class="px-4 py-2 rounded"
      >
        {{ dias }} dias
      </button>
    </div>

    <!-- Cards de resumo -->
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4 mb-8">
      <div class="bg-white p-4 rounded shadow">
        <div class="text-gray-500 text-sm">Coletadas</div>
        <div class="text-3xl font-bold">{{ resumo.total_coletadas }}</div>
      </div>
      <div class="bg-white p-4 rounded shadow">
        <div class="text-gray-500 text-sm">Enviadas</div>
        <div class="text-3xl font-bold text-green-600">{{ resumo.total_enviadas }}</div>
      </div>
      <div class="bg-white p-4 rounded shadow">
        <div class="text-gray-500 text-sm">Taxa aprovação</div>
        <div class="text-3xl font-bold">{{ resumo.taxa_aprovacao }}%</div>
      </div>
      <div class="bg-white p-4 rounded shadow">
        <div class="text-gray-500 text-sm">Receita estimada</div>
        <div class="text-3xl font-bold text-green-600">
          R$ {{ receita.receita_estimada.toFixed(2) }}
        </div>
      </div>
    </div>

    <!-- Principais motivos de rejeição -->
    <div class="bg-white p-4 rounded shadow mb-6">
      <h2 class="font-bold mb-3">Motivos de rejeição</h2>
      <div v-for="r in rejeicoes" :key="r.motivo_rejeicao" class="flex justify-between py-1 border-b">
        <span class="text-gray-600">{{ r.motivo_rejeicao }}</span>
        <span class="font-bold">{{ r.total }}</span>
      </div>
    </div>

    <!-- CTR por categoria -->
    <div class="bg-white p-4 rounded shadow">
      <h2 class="font-bold mb-3">CTR por categoria</h2>
      <div v-for="c in ctr_por_categoria" :key="c.categoria" class="flex justify-between py-1 border-b">
        <span class="text-gray-600">{{ c.categoria }}</span>
        <span>{{ c.cliques }} cliques | <strong>{{ c.ctr }}% CTR</strong></span>
      </div>
    </div>
  </div>
</template>
```

---

## Checklist final da Fase 5

- [ ] `ServicoDashboard.php` criado com todas as queries
- [ ] `DashboardController.php` criado
- [ ] Rota `/dashboard` adicionada
- [ ] Componente Vue do dashboard criado
- [ ] Cards de resumo exibindo dados reais
- [ ] Filtros de período (7, 30, 90 dias) funcionando
- [ ] Motivos de rejeição listados corretamente
- [ ] CTR por categoria calculado
- [ ] Receita estimada exibida com nota de que é estimativa
- [ ] Cache de 5 minutos ativo (verificar via `php artisan cache:clear`)

**Fase 5 concluída → WhatPromo completo 🚀**
