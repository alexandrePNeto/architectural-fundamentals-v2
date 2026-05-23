# 4. Fitness Function para Barrar Cross-Schema Joins

Date: 2026-05-23

## Status

Accepted

## Context

A estratégia de banco único com schemas lógicos por domínio (ADR-002) cria um risco arquitetural amplificado pelo monolito modular (ADR-001): com todos os módulos rodando no mesmo processo Python e acessando o mesmo banco de dados, um desenvolvedor pode — por descuido ou desconhecimento — escrever uma query que faz join entre schemas de domínios diferentes diretamente no banco. Isso violaria os limites entre módulos, criaria acoplamento de dados não intencional e comprometeria a capacidade de extração futura de módulos como serviços independentes, bem como a expansão regional que depende de schemas independentes por domínio.

No monolito modular, ao contrário de uma arquitetura baseada em serviços, não há fronteira de rede separando os módulos — o único mecanismo de enforcement de limite entre domínios no banco é a disciplina de código. Isso torna a automação dessa verificação ainda mais crítica.

A restrição por usuário de banco (cada módulo com permissões apenas no próprio schema) foi considerada, mas descartada: o time não possui ambiente de staging e gerenciar permissões de banco no ambiente local de cada desenvolvedor introduziria risco operacional alto — uma configuração incorreta derrubaria o módulo ou o worker em produção com erro de permissão negada, sem possibilidade de validação prévia.

## Decision

Implementar uma fitness function automatizada em duas camadas:

**Camada 1 — Script de análise estática no CI/CD (GitHub Actions):**
Um script Python que varre todos os arquivos `.py` e `.sql` do repositório em cada pull request, detectando padrões de join entre schemas distintos. Se encontrado, o pipeline quebra e o PR é bloqueado antes de chegar ao code review.

**Camada 2 — Template de pull request com checklist arquitetural:**

```markdown
# .github/pull_request_template.md
## Checklist arquitetural

- [ ] Este PR não contém joins entre schemas de domínios diferentes
- [ ] Este PR não acessa o schema de outro módulo diretamente
- [ ] Comunicação entre módulos passa exclusivamente pelas interfaces públicas definidas por cada módulo
- [ ] Novos acessos ao banco estão restritos ao schema do próprio módulo
```

## Consequences

### O que fica mais fácil

- Violações arquiteturais de acoplamento entre schemas são detectadas automaticamente antes do code review, sem custo humano adicional no dia a dia.
- O template de PR cria consciência ativa no time sobre os limites de módulo a cada contribuição, reforçando a cultura arquitetural de forma incremental.
- A abordagem é compatível com o ambiente atual: funciona em desenvolvimento local sem qualquer configuração adicional e não depende de staging.
- A fitness function documenta de forma executável a intenção arquitetural — qualquer desenvolvedor novo pode ler o script e o checklist para entender os limites de módulo sem precisar de onboarding verbal.

### O que fica mais difícil ou introduz riscos

- **Cobertura incompleta da análise estática**: o script cobre os casos mais comuns (joins explícitos em SQL literal e em ORM), mas não é infalível. Queries construídas dinamicamente via concatenação de strings ou geradas por meta-programação não serão detectadas automaticamente. Esses casos dependem da segunda camada (checklist de PR) e da maturidade do time.
- **Manutenção do script**: à medida que novos padrões de acesso ao banco forem introduzidos (novos ORMs, query builders, bibliotecas de migração), o script precisará ser atualizado para cobri-los. Se não mantido, pode dar falsa sensação de segurança.
- **Custo de falsos positivos**: o script pode gerar falsos positivos em casos legítimos — por exemplo, uma query de relatório no Módulo da Matriz que agrega dados de múltiplos schemas de forma intencional e documentada. O time precisará de um mecanismo explícito de exceção (ex: comentário de supressão) para esses casos, sem criar brechas para abusos.
- **Não cobre acoplamento lógico**: a fitness function barra acoplamento de dados via SQL, mas não detecta acoplamento lógico entre módulos via código Python — por exemplo, um módulo importando diretamente a camada de repositório de outro. Esse risco complementar deve ser tratado por convenção de imports e, eventualmente, por uma segunda fitness function de análise de dependências entre módulos Python.
- **Dependência de cultura**: a Camada 2 (checklist de PR) depende de disciplina humana. Em momentos de pressão de entrega, checklists tendem a ser marcados sem verificação real. A Camada 1 é a salvaguarda efetiva; a Camada 2 é complementar.