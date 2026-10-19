# Minimo

Rede social de ideias curtas, opiniões e conversas. Interface responsiva em HTML/CSS/JavaScript, usando Supabase Auth e PostgreSQL.

## Projeto Supabase

- Project ref: ymuctwbonaegjfzawvnv
- URL: https://ymuctwbonaegjfzawvnv.supabase.co
- Região: São Paulo (sa-east-1)
- Painel: https://supabase.com/dashboard/project/ymuctwbonaegjfzawvnv

A chave publishable fica no cliente web por design. Nunca adicione service_role, chaves secretas ou credenciais de servidor ao repositório.

## Executar localmente

Como o navegador importa o SDK Supabase como módulo ES, execute a partir de um servidor HTTP, não abrindo o arquivo via file://.

    python -m http.server 8080

Abra http://localhost:8080.

## Funcionalidades

- Cadastro e login com Supabase Auth
- Feed de publicações
- Criar e excluir publicações próprias
- Curtidas e comentários
- Seguir perfis
- Notificações de novos seguidores, curtidas e comentários
- Editar nome de exibição e bio
- Políticas RLS nas tabelas expostas

## Banco de dados

O esquema implantado está documentado em supabase/schema.sql. As seis tabelas públicas têm Row Level Security habilitado. Os triggers criam perfil no cadastro e notificações para interações.

## Antes de produção

1. No Supabase, configure Authentication → URL Configuration com os domínios locais e de produção.
2. Defina a política de confirmação de e-mail desejada em Authentication.
3. Teste cadastro, login, logout e operações com duas contas diferentes.
4. Adicione recuperação de senha, moderação, rate limiting, paginação e testes automatizados.
5. Ative HTTPS na hospedagem.
