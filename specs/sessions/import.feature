Feature: Import sessions
  As a developer with Claude instances in terminal windows and years of finished sessions
  I want to choose which of them become cards
  So that the board shows my work without being flooded with every transcript

  Background:
    Given the Kanban Code application is running
    And the board lists only the cards the app started or the kanban CLI registered

  # ── Running ──

  Scenario: A live Claude instance is offered under "Running"
    Given <profile>/sessions/<pid>.json says kind "interactive" for session "s1"
    And process <pid> is alive
    And a transcript for "s1" exists in an enabled profile
    When I open Import sessions
    Then "s1" is listed under "Running in a terminal" with the name Claude gave it
    And it is ticked

  Scenario: A dead pid is not offered
    Given <profile>/sessions/<pid>.json exists and process <pid> is gone
    When I open Import sessions
    Then the session is not listed as running

  Scenario: A reused pid is not offered
    Given process <pid> is alive but started at another time than "procStart" in the file
    When I open Import sessions
    Then the session is not listed as running

  Scenario: A running instance without a transcript is not offered
    Given a live instance whose transcript is not on disk yet
    When I open Import sessions
    Then it is not listed

  Scenario: A disabled profile is not read
    Given the profile has enabled set to false
    When I open Import sessions
    Then none of its running or finished sessions are listed

  Scenario: A file that cannot be parsed does not break the dialog
    Given <profile>/sessions/<pid>.json holds text that is not JSON
    When I open Import sessions
    Then the other sessions are still listed

  # ── Finished ──

  Scenario: Finished sessions are grouped by project and profile
    Given sessions of two projects and two profiles
    When I open Import sessions
    Then each project and profile pair is a group, newest session first
    And a project with no running terminal is a group like any other

  Scenario: The ten newest of each group are ticked
    Given a project with 15 finished sessions
    When I open Import sessions
    Then the ten newest are ticked and "Show 5 more" shows the rest unticked

  Scenario: Sessions that need no card are not offered
    Given a session already held by a card, a deleted session, a headless run (claude -p) and a Codex session
    When I open Import sessions
    Then none of them is listed

  # ── Import ──

  Scenario: Only ticked sessions become cards
    Given 3 sessions are listed and 2 are ticked
    When I press "Import 2"
    Then two cards exist with the session id, the project folder and the profile of their transcript
    And a running session's card is named as Claude named it

  Scenario: Importing twice makes one card
    Given a session was imported
    When the same session is imported again
    Then no second card exists for its session id

  Scenario: An imported card survives the archiving of discovery-only cards
    Given an imported card
    When the board archives the cards that only discovery created
    Then the imported card stays where it is

  Scenario: The column comes from the card's activity
    Given an imported session last active 3 days ago
    Then its card is in All Sessions
    And a session active an hour ago is in Waiting

  # ── Resume ──

  Scenario: Resume asks first while the terminal still runs
    Given an imported card whose session still runs in an iTerm window
    When I resume the card
    Then a dialog says the session is already running in a terminal
    And no second Claude starts until I choose "Resume anyway"
