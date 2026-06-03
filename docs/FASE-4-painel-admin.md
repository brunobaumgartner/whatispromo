# WhatPromo — Fase 4: Painel Admin (Laravel + Vue)

## Objetivo
Interface web para gerenciar ofertas, grupos, configurações e ver histórico
de envios. Só implementar após o MVP estar gerando retorno financeiro.

## Pré-requisitos
- Fases 1, 2 e 3 concluídas
- PHP 8.3 + Composer instalados
- Node.js 20 + npm instalados
- MVP validado com retorno financeiro

---

## Telas do MVP do painel

| Tela | Rota | O que faz |
|---|---|---|
| Ofertas | `/ofertas` | Lista paginada com filtros + aprovar/rejeitar manual |
| Grupos | `/grupos` | CRUD de grupos WhatsApp/Telegram |
| Disparos | `/disparos` | Histórico de envios com status e cliques |
| Configurações | `/configuracoes` | Trocar PROVEDOR_IA sem acessar o servidor |

> O dashboard analítico é a Fase 5 — não implementar aqui.

---

## Etapa 1 — Criar projeto Laravel

```bash
cd /srv/whatpromo
composer create-project laravel/laravel painel
cd painel

# Instala autenticação simples (login/logout)
composer require laravel/breeze --dev
php artisan breeze:install vue   # Vue com Inertia.js
npm install && npm run build
```

---

## Etapa 2 — Configurar .env do Laravel

No arquivo `/srv/whatpromo/painel/.env`, configure:

```env
APP_NAME=WhatPromo
APP_ENV=local
APP_KEY=           # Gerado automaticamente pelo Laravel
APP_DEBUG=true
APP_URL=http://localhost:8000

DB_CONNECTION=mysql
DB_HOST=127.0.0.1  # localhost — o painel roda fora do Docker
DB_PORT=3306
DB_DATABASE=whatpromo_db
DB_USERNAME=whatpromo_usuario
DB_PASSWORD=senha_forte_aqui
```

**Por que o painel roda fora do Docker?**
O Laravel tem seu próprio servidor de desenvolvimento (`php artisan serve`).
Na fase local, é mais simples rodar diretamente. Na Oracle/VPS,
o Nginx vai servir os arquivos estáticos compilados.

---

## Etapa 3 — Criar Models

Crie `/srv/whatpromo/painel/app/Models/Oferta.php`:

```php
<?php
// WhatPromo — Model de ofertas
// Representa uma linha da tabela ofertas no banco.
// Usando o nome em português conforme convenção do projeto.

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class Oferta extends Model
{
    // Nome da tabela em português
    protected $table = 'ofertas';

    // Campos que podem ser preenchidos via formulário
    protected $fillable = [
        'hash_url', 'titulo', 'loja', 'categoria',
        'preco_original', 'preco_promocional', 'percentual_desconto',
        'cupom', 'url_original', 'url_afiliado', 'url_curta',
        'pontuacao_ia', 'provedor_ia', 'mensagem_wa',
        'status', 'motivo_rejeicao',
    ];

    // Campos de data que o Laravel gerencia automaticamente
    protected $dates = ['raspado_em', 'enviado_em', 'expira_em'];

    // Desativa timestamps automáticos do Laravel (created_at/updated_at)
    // pois usamos raspado_em e enviado_em com nomes diferentes
    public $timestamps = false;

    // Relacionamento: uma oferta tem vários disparos
    public function disparos()
    {
        return $this->hasMany(Disparo::class, 'oferta_id');
    }
}
```

---

## Etapa 4 — Criar Controllers

Crie `/srv/whatpromo/painel/app/Http/Controllers/OfertaController.php`:

```php
<?php
// WhatPromo — Controller de ofertas
// Gerencia a listagem, filtros e ações manuais sobre as ofertas.

namespace App\Http\Controllers;

use App\Models\Oferta;
use Illuminate\Http\Request;
use Inertia\Inertia;

class OfertaController extends Controller
{
    // Exibe lista paginada com filtros
    public function index(Request $request)
    {
        $ofertas = Oferta::query()
            ->when($request->status,    fn($q) => $q->where('status', $request->status))
            ->when($request->loja,      fn($q) => $q->where('loja', $request->loja))
            ->when($request->categoria, fn($q) => $q->where('categoria', $request->categoria))
            ->orderBy('raspado_em', 'desc')
            ->paginate(25);

        return Inertia::render('Ofertas/Index', [
            'ofertas' => $ofertas,
            'filtros' => $request->only(['status', 'loja', 'categoria']),
        ]);
    }

    // Aprovação manual de oferta (fora do pipeline automático)
    public function aprovar(Oferta $oferta)
    {
        $oferta->update(['status' => 'aprovada', 'motivo_rejeicao' => null]);
        return back()->with('mensagem', 'Oferta aprovada manualmente.');
    }

    // Rejeição manual
    public function rejeitar(Oferta $oferta)
    {
        $oferta->update(['status' => 'rejeitada', 'motivo_rejeicao' => 'rejeitada_manualmente']);
        return back()->with('mensagem', 'Oferta rejeitada.');
    }

    // Força envio imediato de uma oferta específica
    public function enviarAgora(Oferta $oferta)
    {
        // Chama o endpoint REST do Airflow para executar a task de disparo
        // com o ID desta oferta específica
        // Implementação detalhada na Fase 4
        return back()->with('mensagem', 'Envio solicitado.');
    }
}
```

---

## Etapa 5 — Definir rotas

No arquivo `/srv/whatpromo/painel/routes/web.php`:

```php
<?php
// WhatPromo — Rotas do painel admin
// Todas protegidas por autenticação (middleware 'auth')

use App\Http\Controllers\OfertaController;
use App\Http\Controllers\GrupoController;
use App\Http\Controllers\DisparoController;
use App\Http\Controllers\ConfiguracaoController;

// Redireciona raiz para /ofertas
Route::redirect('/', '/ofertas');

Route::middleware('auth')->group(function () {

    // Ofertas
    Route::get('/ofertas',                  [OfertaController::class, 'index'])->name('ofertas.index');
    Route::post('/ofertas/{oferta}/aprovar', [OfertaController::class, 'aprovar'])->name('ofertas.aprovar');
    Route::post('/ofertas/{oferta}/rejeitar',[OfertaController::class, 'rejeitar'])->name('ofertas.rejeitar');
    Route::post('/ofertas/{oferta}/enviar',  [OfertaController::class, 'enviarAgora'])->name('ofertas.enviar');

    // Grupos
    Route::resource('grupos', GrupoController::class);

    // Disparos
    Route::get('/disparos', [DisparoController::class, 'index'])->name('disparos.index');

    // Configurações
    Route::get('/configuracoes',  [ConfiguracaoController::class, 'index'])->name('configuracoes.index');
    Route::post('/configuracoes', [ConfiguracaoController::class, 'salvar'])->name('configuracoes.salvar');
});
```

---

## Etapa 6 — Subir o painel localmente

```bash
cd /srv/whatpromo/painel

# Gera a APP_KEY
php artisan key:generate

# Inicia o servidor de desenvolvimento
php artisan serve
# Acesse: http://localhost:8000
```

---

## Etapa 7 — Adicionar ao docker-compose (Oracle/VPS)

Quando for para a Oracle ou VPS, o painel entra no docker-compose:

```yaml
  painel_laravel:
    image: php:8.3-fpm
    container_name: whatpromo_painel
    restart: unless-stopped
    working_dir: /var/www
    volumes:
      - ./painel:/var/www
    depends_on:
      banco_dados:
        condition: service_healthy
```

E o Nginx roteia o tráfego:
- `dominio.com` → painel Laravel
- `dominio.com/airflow` → Airflow UI

---

## Checklist final da Fase 4

- [ ] Projeto Laravel criado com Breeze + Vue + Inertia
- [ ] `.env` do Laravel configurado com dados do banco
- [ ] Model `Oferta` criado
- [ ] `OfertaController` com index, aprovar, rejeitar, enviarAgora
- [ ] Rotas definidas em português
- [ ] `php artisan serve` rodando sem erros
- [ ] Login funcionando
- [ ] Tela `/ofertas` listando ofertas do banco
- [ ] Tela `/grupos` com CRUD funcionando
- [ ] Tela `/disparos` com histórico
- [ ] Tela `/configuracoes` permitindo trocar PROVEDOR_IA

**Fase 4 concluída → partir para a Fase 5 (Dashboard Analítico)**
