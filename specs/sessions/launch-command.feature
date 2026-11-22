Feature: Launch Command Per Card
  As a developer who signs in to some profiles through CodeMie SSO
  I want a card to remember how it was started (plain claude or codemie-claude)
  So that every resume uses the same command and a profile supplies the default

  Background:
    Given the Kanban Code application is running
    And tmux is installed
    And Settings lists the launch command "Claude Code via CodeMie" with the command "codemie-claude"
    And the "Omicrown" profile has the default launch command "Claude Code via CodeMie"
    And the "Omicrown" profile has the project root "~/Repos/Omicrown"
    And the "~/.claude" profile has no default launch command

  # ── Default and choice ──

  Scenario: The profile of the project supplies the default in the dialog
    Given a backlog card whose project is "~/Repos/Omicrown/kanban-code"
    When I click "Start"
    Then the launch confirmation dialog should show a "Launch with" popup
    And the popup should be preselected as "Claude Code via CodeMie"
    And the Command field should start with "codemie-claude"

  Scenario: Changing the choice refreshes the Command field
    Given the launch confirmation dialog is open and I have not edited the Command field
    When I pick "Claude Code" in the "Launch with" popup
    Then the Command field should start with "claude"
    When I pick "Claude Code via CodeMie" again
    Then the Command field should start with "codemie-claude"

  Scenario: A pick made by hand survives a project switch while it is still listed
    Given I open New Task and pick "Claude Code" in the "Launch with" popup
    When I switch the project to one under the "Omicrown" project root
    Then the popup should still show "Claude Code"
    Because the choice is made in the dialog and the profile only supplies the default

  Scenario: The choice is kept on the card
    Given the launch confirmation dialog shows "Claude Code via CodeMie"
    When I click "Launch"
    Then the card should store the launch command "codemie-claude"
    And Claude should be started in tmux with "codemie-claude" followed by the app's flags

  Scenario: Plain Claude Code is the meaning of no stored command
    Given the launch confirmation dialog shows "Claude Code"
    When I click "Launch"
    Then the card should store no launch command
    And Claude should be started in tmux with "claude"

  # ── Resume ──

  Scenario: Resume uses the command stored on the card
    Given a card was launched with "codemie-claude" and has a session
    When I resume the card from the card detail
    Then the resume command should start with "codemie-claude"
    And it should end with "--resume" and the session id

  Scenario: Resume from the master engine uses the command stored on the card
    Given a card was launched with "codemie-claude" and has a session
    When the master engine resumes the card
    Then the resume command should start with "codemie-claude"

  Scenario: Editing Settings later does not change a started card
    Given a card was launched with "codemie-claude"
    When I delete or rename the launch command "Claude Code via CodeMie" in Settings
    And I resume the card
    Then the resume command should still start with "codemie-claude"
    Because the card stores the command itself, not an id from Settings

  Scenario: A card with a session and no stored command stays plain claude
    Given a card made before this feature, or an imported or found session, has a session
    And its project is under the "Omicrown" project root
    When I resume the card
    Then the resume command should start with "claude"
    And the profile default should not be applied
    Because a CodeMie session cannot be told apart from a plain one after the fact

  # ── Starting without a dialog ──

  Scenario: A card that has never launched takes the profile default
    Given a backlog card under the "Omicrown" project root
    When I drag it to "In Progress" without a dialog
    Then it should start with "codemie-claude"
    And the card should store the launch command "codemie-claude"

  Scenario: A spawned child card takes the profile default
    Given a card spawned by another card has no session
    And its project is under the "Omicrown" project root
    When it starts
    Then it should start with "codemie-claude"

  Scenario: A project outside every profile root gets plain claude
    Given a backlog card whose project is "~/Scratch/other"
    When I open the launch confirmation dialog
    Then the popup should be preselected as "Claude Code"
    And the Command field should start with "claude"

  Scenario: A blank launch command is plain claude
    Given a launch command in Settings with a blank command
    When a card is started with it
    Then Claude should be started with "claude"

  # ── Hand edit of the Command field ──

  Scenario: A hand-edited Command field remembers a known launcher
    Given the launch confirmation dialog shows "Claude Code"
    When I edit the Command field to "FOO=1 codemie-claude --dangerously-skip-permissions"
    And I click "Launch"
    Then the card should store the launch command "codemie-claude"
    Because the first token equal to "claude" or to a launcher command in Settings is stored

  Scenario: A hand-edited Command field with no known token stores nothing
    Given the launch confirmation dialog shows "Claude Code via CodeMie"
    When I edit the Command field to "langwatch run -- my-tool"
    And I click "Launch"
    Then the card should store no launch command

  # ── Forks, remote and other assistants ──

  Scenario: A fork of a CodeMie card resumes with CodeMie
    Given a card launched with "codemie-claude" has a session
    When I fork the session
    Then the fork command should start with "codemie-claude"
    And the forked card should store the launch command "codemie-claude"
    Because a plain claude in a profile with no login of its own stops with "Not logged in"

  Scenario: A fork of a plain card stays plain
    Given a card launched with "claude" has a session
    When I fork the session
    Then the fork command should start with "claude"
    And the forked card should store no launch command
    Because a plain card must never start asking for SSO

  Scenario: A fork into another assistant copies no launch command
    Given a card launched with "codemie-claude" has a session
    When I fork the session into Codex
    Then the forked card should store no launch command

  Scenario: Remote runs store nothing and the popup is disabled
    Given "Run remotely" is checked in the launch confirmation dialog
    Then the "Launch with" popup should be disabled
    And a note should say "applies to local runs"
    When I click "Launch"
    Then the remote command should use plain "claude"
    And the card should store no launch command

  Scenario: Rush runs store nothing
    When I start a card in rush mode
    Then the command should use plain "claude"
    And the card should store no launch command

  Scenario: The popup is hidden for Codex and Gemini
    Given I pick "Codex" as the assistant in the dialog
    Then the "Launch with" popup should not be visible
    And the card should store no launch command
    When I pick "Gemini" as the assistant
    Then the "Launch with" popup should not be visible
    And the command should not use "codemie-claude"

  Scenario: Switching the assistant away from Claude Code clears the choice
    Given the popup shows "Claude Code via CodeMie"
    When I switch the assistant to "Codex"
    Then the Command field should follow the Codex command
    When I switch the assistant back to "Claude Code"
    Then the popup should be preselected from the profile again

  # ── Compatibility ──

  Scenario: Old settings and cards load unchanged
    Given a settings.json and a links.json written before this feature
    When the application starts
    Then every card should load with no stored launch command
    And Settings should offer "Claude Code" and, once, the seeded "Claude Code via CodeMie"
