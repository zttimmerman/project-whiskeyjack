---
id: pickup-feedback
title: "Show what the player picked up, and when a pickup can be taken"
status: proposed
kind: feature
targets: []
after: [level1-spoke-spacing]
phase: gameplay-2
branch: null
pr: null
updated: 2026-10-08
---
## Goal

`scenes/items/ItemPickup` (level1-spoke-spacing) adds its item to the inventory silently: no "Found: Health Potion" line, no interact prompt when the player faces it, and no sound. The payoff should read as one.

## Scope

- A HUD line on `picked_up` (the item's name), and a prompt while the interact ray finds a pickup
- A pickup sound through `AudioManager.play_ui` if a CC0 one fits; no paid assets
- Whether a full inventory says so is a design question for the user

## Acceptance

- Taking the side room's potion shows its name and plays a sound; facing it shows the prompt

## Serves

Design bible §4 (a payoff in sight after a fight).
