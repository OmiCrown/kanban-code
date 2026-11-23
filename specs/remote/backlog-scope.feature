Feature: Backlog scope
  As the owner of a Mac with a coding assistant in a session
  I want an agent to be able to file cards in my backlog and nothing else
  So that I review its proposals and launch the ones I want myself

  Background:
    Given the remote control server is on
    And a device is paired with the "backlog" scope

  Scenario Outline: A backlog token makes the calls that file a card
    When the device calls "<route>"
    Then the call is served

    Examples:
      | route          |
      | GET /v1/me     |
      | GET /v1/machines |
      | POST /v1/tasks |

  Scenario: A card is created in the backlog
    When the device posts a task with launch false
    Then the answer is 201
    And the card is in the backlog
    And no assistant is started

  Scenario Outline: A task that would start work is refused
    When the device posts a task with <body>
    Then the answer is 403 "<message>"
    And no card is created

    Examples:
      | body                              | message                                                         |
      | launch true                       | the backlog scope only creates backlog cards: send launch=false |
      | no launch field                   | the backlog scope only creates backlog cards: send launch=false |
      | machine another machine           | the backlog scope cannot choose another machine                 |
      | project https://github.com/a/b    | the backlog scope cannot name a repository URL as the project   |
      | project git@github.com:a/b.git    | the backlog scope cannot name a repository URL as the project   |

  Scenario: The machine this Mac is called passes
    When the device posts a task with launch false and machine set to this Mac's name
    Then the answer is 201

  Scenario Outline: Every other call is refused
    When the device calls "<route>"
    Then the answer is 403

    Examples:
      | route                        |
      | GET /v1/board                |
      | GET /v1/cards/search         |
      | GET /v1/cards/{id}/transcript |
      | POST /v1/cards/{id}/prompt   |
      | POST /v1/cards/{id}/resume   |
      | POST /v1/cards/{id}/move     |
      | DELETE /v1/cards/{id}        |
      | GET /v1/cards/{id}/terminal  |
      | POST /v1/cli                 |
      | POST /v1/vault/secrets       |

  Scenario: A route added later is refused until it is listed
    When the device calls a route the backlog list does not name
    Then the answer is 403

  Scenario: The device never acts for the owner
    When the device sends a request with "X-Kanban-For-Owner: 1"
    Then the Mac is not kept awake for it
