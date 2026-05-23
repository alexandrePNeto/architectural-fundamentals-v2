# 12. Fitness Functions para Proteção de Limites Arquiteturais

Date: 2026-05-12

## Status

Accepted

## Context

O monolito modular do CWRents (ADR-001) possui dois conjuntos de limites arquiteturais que precisam ser preservados ao longo da evolução do sistema:

**Limite 1 — Domínio vs Infraestrutura (ADR-005):** o domínio de cada módulo deve permanecer desacoplado de frameworks, SDKs externos e tecnologias de infraestrutura. Sem enforcement automático, bibliotecas como SQLAlchemy, FastAPI, RabbitMQ e SDKs de pagamento podem ser importadas diretamente no domínio, acumulando acoplamento tecnológico silenciosamente.

**Limite 2 — Acoplamento entre módulos:** cada módulo deve ser acessado exclusivamente pela sua interface pública — o conjunto de serviços e contratos que o módulo expõe intencionalmente para os demais. Um módulo não pode importar diretamente a camada de domínio, infraestrutura ou repositórios internos de outro módulo. Esse limite é análogo ao conceito de Bounded Context do DDD: cada módulo é dono do seu domínio e expõe apenas o que decide tornar público.

Em um monolito, nenhum dos dois limites é imposto pela arquitetura de processo — ambos dependem exclusivamente de disciplina de código. A proximidade de todos os módulos na mesma base de código torna o acoplamento acidental trivialmente fácil: um import errado é suficiente para violar anos de decisões arquiteturais. Sem automação, esses limites degradam gradualmente sob pressão de entrega.

## Decision

Implementar fitness functions automatizadas cobrindo os dois limites arquiteturais, em duas camadas de validação.

### Camada 1 — Scripts de análise estática no CI/CD (GitHub Actions)

Dois scripts Python executados em cada pull request:

**Script A — Proteção domínio vs infraestrutura:**
Varre os diretórios `<modulo>/dominio/` de todos os módulos (aluguel, pagamento, cadastro, fiscal, notificacoes, matriz) e bloqueia o PR se detectar imports de bibliotecas de infraestrutura (ex: `sqlalchemy`, `fastapi`, `pika`, `httpx`, SDKs externos).

**Script B — Proteção de acoplamento entre módulos:**
Varre todos os módulos e valida que nenhum arquivo importa diretamente de camadas internas de outro módulo. A regra é: imports entre módulos só são permitidos a partir do pacote público de cada módulo (`<modulo>/public/` ou equivalente definido por convenção). Imports de `<modulo_a>/dominio/`, `<modulo_a>/infraestrutura/` ou `<modulo_a>/repositorios/` a partir de qualquer arquivo de `<modulo_b>/` são proibidos e bloqueiam o PR.

### Camada 2 — Revisão arquitetural obrigatória no Pull Request

Todo PR deverá validar explicitamente:

```markdown
## Checklist arquitetural

- [ ] O domínio de nenhum módulo depende de frameworks ou SDKs externos
- [ ] Integrações externas estão isoladas na camada de infraestrutura do respectivo módulo
- [ ] Repositories foram utilizados para persistência — sem ORM models no domínio
- [ ] Nenhum módulo acessa camadas internas de outro módulo diretamente
- [ ] Comunicação entre módulos passa exclusivamente pelas interfaces públicas de cada módulo
- [ ] Novos contratos públicos entre módulos estão documentados e são intencionais
```

## Consequences

### O que fica mais fácil

- Ambos os limites arquiteturais — domínio vs infraestrutura e acoplamento entre módulos — são detectados automaticamente antes do code review, sem custo humano adicional no dia a dia.
- A extração futura de qualquer módulo como serviço independente é facilitada: módulos com acoplamento contido nas suas interfaces públicas têm fronteiras bem definidas e previsíveis para extração.
- A fitness function do Script B torna explícito o conceito de interface pública de módulo, forçando o time a decidir conscientemente o que cada módulo expõe — em vez de deixar isso emergir de forma implícita ao longo do tempo.
- Os scripts servem como documentação executável dos limites: novos desenvolvedores conseguem entender os contratos arquiteturais lendo o código de validação, sem depender de onboarding verbal.
- A cobertura se aplica a todos os módulos de forma uniforme e contínua, sem necessidade de revisão manual em cada PR.

### O que fica mais difícil ou introduz riscos

- **Cobertura incompleta da análise estática**: os scripts cobrem imports explícitos, mas não detectam acoplamento via imports dinâmicos, `importlib`, factories que retornam tipos internos de outro módulo, ou acoplamento conceitual (ex: um módulo que replica a estrutura de dados de outro sem importá-lo). Esses casos dependem da Camada 2 e da maturidade do time.
- **Definição e manutenção da interface pública de cada módulo**: o Script B exige que cada módulo tenha uma convenção clara de o que é público e o que é interno. Essa definição precisa ser mantida ativamente — à medida que novos contratos entre módulos surgem, a interface pública precisa ser atualizada de forma intencional, e não por acidente.
- **Manutenção contínua dos scripts**: novas bibliotecas de infraestrutura e novos módulos precisam ser incluídos nas listas de verificação manualmente. Scripts desatualizados oferecem falsa sensação de segurança.
- **Falsos positivos em casos legítimos**: alguns casos podem gerar falsos positivos — por exemplo, um módulo que usa um tipo compartilhado de outro módulo de forma intencional e documentada. O time precisará de um mecanismo explícito de exceção para esses casos, sem criar precedente para contornar a validação de forma abusiva.
- **Escalabilidade do checklist**: em PRs que tocam múltiplos módulos simultaneamente, a revisão manual do checklist pode se tornar superficial. A Camada 1 é a salvaguarda efetiva; a Camada 2 é complementar e educativa.
- **Não cobre acoplamento de dados entre módulos**: os scripts protegem o código Python, mas não detectam acoplamento via banco de dados — por exemplo, um módulo que acessa a tabela de outro módulo diretamente via SQL raw. Esse risco é tratado pela ADR-004 (fitness function de cross-schema joins), que opera em conjunto com esta ADR.

## Alternativas descartadas

Arquitetura hexagonal completa com ports e adapters avançados foi descartada por adicionar complexidade excessiva ao contexto atual do projeto.

Restrição por permissões de importação via ferramentas como `import-linter` foi considerada, mas depende de configuração adicional por ambiente e introduz dependência de ferramenta de desenvolvimento que o time precisaria manter. Os scripts customizados no CI/CD oferecem controle equivalente com menor fricção de adoção.

Ausência total de validação arquitetural foi descartada porque permitiria degradação gradual e silenciosa dos dois limites ao longo da evolução do monolito — risco especialmente alto em bases de código compartilhadas por múltiplos módulos sob pressão de entrega contínua.