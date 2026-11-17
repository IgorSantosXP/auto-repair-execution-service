# language: pt
Funcionalidade: Execução da ordem de serviço como participante da saga
  Como Execution Service
  Quero reservar as peças e conduzir a execução quando o OS Service mandar iniciar
  Para que a oficina só trabalhe em ordens pagas e com estoque garantido

  Contexto:
    Dado que o catálogo tem a peça "oleo-5w30" com 10 unidades em estoque

  Cenário: Reserva de estoque e execução completa
    Quando o comando "execution.start" chega para a OS "os-1" com 2 unidades de "oleo-5w30"
    Então o estoque de "oleo-5w30" passa a ser 8
    E o evento "execution.queued" é publicado para o OS Service
    Quando o mecânico avança a execução da OS "os-1" por diagnóstico, reparo e finalização
    Então a execução da OS "os-1" fica com status "finished"
    E os eventos "execution.diagnosis_started, execution.repair_started, execution.finished" são publicados em ordem

  Cenário: Estoque insuficiente dispara a compensação da saga
    Quando o comando "execution.start" chega para a OS "os-2" com 50 unidades de "oleo-5w30"
    Então o estoque de "oleo-5w30" continua 10
    E o evento "execution.failed" é publicado com o motivo "insufficient_stock"
    E a OS "os-2" não entra na fila de execução

  Cenário: Comando duplicado é processado uma única vez
    Quando o comando "execution.start" para a OS "os-3" com 1 unidade de "oleo-5w30" é entregue 2 vezes
    Então o estoque de "oleo-5w30" passa a ser 9
    E apenas 1 evento "execution.queued" é publicado
