===============================================================================
WireGuard Control Plane — Global Contracts
===============================================================================

This file defines all non-negotiable invariants for the WireGuard control plane.

It is documentation-as-law.
It contains no executable logic.
It MUST be kept in Git and reviewed like code.

All compiler, renderer, checker, and deployment scripts MUST comply with
these contracts.


-------------------------------------------------------------------------------
CONTRACT: Scope & applicability
-------------------------------------------------------------------------------

This document defines invariants for all scripts deployed to the router.

Rules:

  - All scripts deployed to the router MUST comply with these contracts
  - Control-plane scripts are a strict subset of this scope
  - Script-specific constraints MAY be defined in additional contracts
    but MUST NOT weaken global invariants
  - Contracts apply exclusively to artifacts, scripts, and processes
    within this scope
  - External systems are out of scope unless explicitly referenced
  - No contract may be interpreted beyond its declared scope


Generalization:

  - Contracts are written to be system-agnostic where possible
  - System-specific details MUST be isolated to dedicated contracts

Any interpretation that extends a contract beyond its declared scope
is a contract violation.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Document structure & formatting
-------------------------------------------------------------------------------

This document uses a single, consistent structural grammar.

Rules:

  - Document-level boundaries MUST use '=' separators
  - Contract sections MUST use '-' separators
  - No other separator styles are permitted
  - All CONTRACT blocks MUST follow the same layout:
      separator
      CONTRACT: <name>
      separator
      body
      separator

Ordering:

  - The document header MUST appear first
  - All CONTRACT blocks MUST appear after the header
  - No content may precede the document header

Formatting is normative:

  - Visual structure is part of the contract
  - Inconsistent formatting is a contract violation
  - Cosmetic drift is forbidden

Any change that introduces a new separator style,
alters block layout, or violates ordering rules
renders the document invalid.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Contract enforcement & failure semantics
-------------------------------------------------------------------------------

All contracts in this document are enforceable invariants.

Rules:

  - Every contract MUST be checkable by at least one script or Make target
  - Checks MUST be deterministic and side-effect free
  - Checks MUST fail loudly on violation
  - Silent degradation is forbidden

Failure semantics:

  - Any detected contract violation MUST abort execution immediately
  - Partial success is forbidden
  - Continuing after a known violation is a contract violation itself

Scope:

  - Preflight checks MUST validate all applicable contracts
  - Deployment MUST NOT proceed if any contract is violated
  - Review MUST reject changes that weaken or bypass enforcement

Contracts that cannot be enforced mechanically
are considered incomplete and invalid.

Design compliance discipline:

  - Implementations MUST satisfy contracts by design, not by exception.
  - Removing, weakening, or bypassing normative comments, assertions,
    or declarations in order to "make code work" is forbidden.
  - If a contract cannot be satisfied without altering design,
    the design MUST be revised.
  - If a contract is impractical, the contract MUST be amended explicitly
    before code changes are accepted.
  - Implementations and reviews MUST NOT rely on assumed or invented
    environment properties; all dependencies MUST be derived from
    declared contracts or verified behavior.

Rationale:

  - Contracts govern architecture, not just syntax.
  - Code that works by ignoring contract intent is invalid by definition.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Change control & evolution
-------------------------------------------------------------------------------

Contracts are stable by default.

Rules:

  - Any contract change MUST be intentional and explicit
  - Changes MUST preserve or strengthen existing invariants
  - Weakening a contract requires explicit justification

Evolution discipline:

  - New contracts MAY be added
  - Existing contracts MUST NOT be silently altered
  - Contract removal is forbidden without replacement

Review semantics:

  - Contract changes MUST be reviewed independently of code changes
  - Code that requires weakening a contract is invalid by definition

Unjustified contract drift is a contract violation.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Runtime tool availability
-------------------------------------------------------------------------------

The router runtime environment MUST provide the following BusyBox tools:
  - awk
  - sha256sum
  - sed

Properties:

  - Tools MUST be available via BusyBox invocation
  - Vendored or standalone binaries are forbidden
  - Scripts MUST invoke tools explicitly via BusyBox
  - PATH-based resolution MUST NOT be relied upon

Rationale:

  - BusyBox is the canonical router toolchain
  - Vendoring duplicates functionality and introduces drift
  - Tool availability MUST be verifiable via direct execution

Any script or Make target that:
  - requires a vendored awk binary
  - rejects BusyBox-provided tools
  - or assumes PATH resolution

is a contract violation.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Canonical storage & disaster recovery
-------------------------------------------------------------------------------

All canonical intent MUST reside on persistent router storage under /jffs/scripts/.

Canonical files:
  - domain.yaml      (domain definitions only)
  - contracts.inc    (this file)
  - Makefile         (orchestration only)

Runtime devices (router, clients) are disposable.
The entire system MUST be reconstructible from NAS backups alone.

WSL is a control-plane execution environment, NOT a source of truth.


-------------------------------------------------------------------------------
CONTRACT: Enumeration model
-------------------------------------------------------------------------------

The system enumerates the full valid state space:

    nodes × interfaces × profiles

There are:
  - no grants
  - no allow-lists
  - no selective enablement

Invalid combinations are excluded ONLY by hard constraints.

All valid combinations MUST be representable in the compiled dump.


-------------------------------------------------------------------------------
CONTRACT: Compiled dumps
-------------------------------------------------------------------------------

The following files are materialized database snapshots:

  - plan.tsv
  - alloc.tsv
  - keys.tsv

Properties:
  - Deterministic
  - Complete (no hidden runtime state)
  - Flat and relational
  - Excel-friendly
  - Never edited by hand
  - Authoritative once generated

If a configuration exists at runtime, it MUST exist in the dump.

Dump emission is OPTIONAL and controlled by:

    WG_DUMP=1

When WG_DUMP is unset or 0, dumps MUST NOT be written.


-------------------------------------------------------------------------------
CONTRACT: TSV encoding
-------------------------------------------------------------------------------

All dump files are UTF-8 encoded TSV with:

  - ASCII TAB (0x09) as field delimiter
  - LF (0x0A) as line terminator
  - No quoting
  - No escaping

Forbidden inside any field:

  - ASCII NUL (0x00)
  - TAB (0x09)
  - LF (0x0A)
  - CR (0x0D)

Quotes (", ') have NO special meaning.

Any violation MUST abort compilation loudly.


-------------------------------------------------------------------------------
CONTRACT: Deterministic ordering
-------------------------------------------------------------------------------

All dump rows MUST be emitted in a stable, deterministic order.

Sorting keys MUST be explicit and consistent across runs.

This guarantees:
  - clean diffs
  - reliable drift detection
  - trustworthy Excel inspection


-------------------------------------------------------------------------------
CONTRACT: Profiles
-------------------------------------------------------------------------------

Profiles are named routing intents.

Properties:
  - Textual identifiers with documented meaning
  - Not OS-specific
  - Not user-specific
  - Not grants
  - Not selections

Profiles describe intent ONLY.
Realization happens at render time.


-------------------------------------------------------------------------------
CONTRACT: Interfaces
-------------------------------------------------------------------------------

The 'iface' field uniquely identifies the WireGuard server endpoint.

There is NO additional server dimension.

Examples:
  - wg1..wg15  → NAS-hosted WireGuard servers
  - wgs        → Router-hosted WireGuard server

All server identity, keys, firewall rules, routing, and deployment
are derived exclusively from 'iface'.


-------------------------------------------------------------------------------
CONTRACT: Key lifecycle
-------------------------------------------------------------------------------

Client keys are scoped to:

    (base, iface)

Keys are:
  - generated idempotently
  - never rotated implicitly

Profile or OS changes MUST NOT affect key identity.


-------------------------------------------------------------------------------
CONTRACT: Renderers
-------------------------------------------------------------------------------

Renderers are dumb consumers of plan.tsv.

Renderers MUST perform:
  - no address math
  - no policy inference
  - no intent resolution

All intent MUST be resolved at compile time.


-------------------------------------------------------------------------------
CONTRACT: Wiring order
-------------------------------------------------------------------------------

WireGuard is the foundational layer.

Dependency order:

  1. WireGuard (identity, routing domains, interfaces)
  2. Firewall / NAT (keyed on WG interfaces)
  3. Higher-level services (e.g. Caddy)

No service above WireGuard may influence WireGuard intent.


-------------------------------------------------------------------------------
CONTRACT: Make orchestration & deployment
-------------------------------------------------------------------------------

Make executes locally (WSL). The router is the canonical runtime store.

Deployment model:
  - Each deployed router artifact MUST have exactly one owning Make target.
  - No two targets may write the same destination path on the router.
  - No overlapping recipes are permitted (single-writer per artifact).

Execution integrity:
  - Any Make target that executes artifacts on the router MUST depend on
    the Make target that installs or updates those artifacts.
  - Executing router-resident scripts without an explicit installation
    dependency is forbidden.
  - Running stale artifacts is a contract violation, regardless of
    apparent runtime success.

Installation semantics:
  - Make MUST NOT use install(1) for router deployment.
  - Deployment MUST be explicit and auditable (scp/ssh or equivalent).
  - Deployment MUST be atomic on the router:
      write to a temporary path, then mv -f into place.

Graph discipline:
  - graph.mk defines dependency order only.
  - Module .mk files may define recipes, but only for artifacts they own.
  - config.mk defines variables only; no targets, no recipes, no side effects.

Concurrency semantics:

  - .NOTPARALLEL is file-local and does NOT propagate across included Makefiles.
  - Any target listed in a .NOTPARALLEL declaration MUST be declared in the same file.
  - Centralizing .NOTPARALLEL in an including file is forbidden.

Structural enforcement:
  - When a Makefile is split, all concurrency constraints MUST be re-established
    in the owning module files.
  - Failure to re-declare required .NOTPARALLEL constraints after a split
    is a contract violation, even if behavior appears unchanged under -j1.

Recursive invocation discipline:

  - Makefile recipes MUST NOT invoke $(MAKE) or make recursively.
  - All dependency relationships MUST be expressed in the static Make graph.
  - Control flow via recursive Make invocation is forbidden.
  - Capability checks and preflight validation MUST be modeled as explicit
    dependencies or standalone verification targets, not invoked imperatively.

Rationale:

  - Recursive Make bypasses dependency visibility.
  - It breaks determinism and auditability.
  - It introduces hidden execution order and side effects.
  - It defeats Make’s core purpose as a declarative build graph.

Any Makefile that invokes $(MAKE) inside a recipe is invalid.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Makefile shell constructs
-------------------------------------------------------------------------------

Makefile recipes MUST NOT use shell here-documents (<<EOF or variants).

Rules:

  - Here-documents are forbidden in all Makefile recipes
  - Multi-line shell logic MUST be expressed using:
      - single-line commands
      - explicit shell scripts
      - or external script files
  - Makefile recipes MUST remain line-oriented and tab-prefixed

Rationale:

  - GNU Make does not parse here-documents reliably
  - Here-documents introduce non-local syntax errors
  - Failures manifest as misleading "missing separator" errors
  - Debugging becomes non-deterministic and error-prone

Enforcement:

  - Any Makefile containing a here-document is invalid
  - Review MUST reject such changes
  - Refactoring to external scripts is mandatory

This is a structural invariant, not a stylistic preference.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: File size & structural limits
-------------------------------------------------------------------------------

No Makefile may exceed 10000 characters.

Rationale:
  - Files beyond this size become non-local to review
  - Ownership boundaries blur
  - Accidental coupling and overlap become likely

Enforcement:
  - If a Makefile exceeds this limit, responsibilities MUST be split
    along existing ownership boundaries.
  - Splitting MUST NOT introduce new behavior, targets, or semantics.
  - The resulting files MUST preserve identical dependency graphs
    and execution behavior.

This is a structural invariant, not a stylistic guideline.
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Documentation correctness
-------------------------------------------------------------------------------

All comments that describe structure, ordering, ownership, or intent
are normative and MUST be correct.

This applies to:
  - File headers
  - Section headers
  - Module inclusion order descriptions
  - Target ownership descriptions
  - Any comment that explains "what this is" or "how this is wired"

In particular:
  - Any comment describing inclusion order MUST exactly match the
    actual include order in the file.
  - Any comment describing ownership or responsibility MUST match
    the actual owning target or module.
  - Any comment describing behavior or semantics MUST reflect
    current reality, not historical intent.

Comments are documentation-as-law:
  - A misleading comment is a contract violation.
  - A stale comment is a bug.
  - Updating code without updating its descriptive comments
    is forbidden.

If code and comments disagree, the system is considered invalid
until corrected.

Enforcement:
  - Any change that alters structure, ordering, ownership, or behavior
    MUST update the corresponding descriptive comments in the same change.
  - Review MUST reject changes where comments and code diverge,
    even if runtime behavior is otherwise correct.

-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Content addressing & hashing
-------------------------------------------------------------------------------

Deployment and drift detection rely on SHA-256 content hashing.

The router platform MUST provide SHA-256 hashing via one of:
  - sha256sum(1)
  - busybox sha256sum

Implementations MUST accept either form.

Requiring a standalone sha256sum binary is forbidden.

Any deployment logic that rejects BusyBox sha256sum
is a contract violation.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
CONTRACT: Non-goals
-------------------------------------------------------------------------------

This document intentionally does NOT define:

  - Performance targets
  - Feature roadmaps
  - User experience guarantees
  - Operational SLAs
  - Organizational policy

Rationale:

  - Contracts define invariants, not aspirations
  - Mixing goals with invariants weakens both
  - Non-goals are explicit to prevent scope creep

Any attempt to encode goals, preferences, or aspirations
as contracts is a contract violation.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
CONTRACT: Execution root & working directory confinement
-------------------------------------------------------------------------------

All control-plane scripts MUST execute with a well-defined execution root.

Rules:

  - Every script deployed to the router MUST explicitly set its working
    directory at startup.
  - The working directory MUST be the directory containing the script itself.
  - Relative paths MUST be resolved exclusively within this directory tree.
  - Reliance on caller-provided working directories is forbidden.

Enforcement:

  - Scripts MUST perform an explicit directory change at startup.
  - Failure to establish the execution root MUST abort execution immediately.

Rationale:

  - Prevents accidental writes to arbitrary filesystem locations
  - Ensures deterministic artifact placement
  - Eliminates execution-context ambiguity
  - Makes side effects auditable and inspectable

Any script that emits files relative to an implicit or inherited working
directory is a contract violation.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
CONTRACT: Write confinement & side-effect boundaries
-------------------------------------------------------------------------------

Control-plane scripts MUST NOT write outside their declared ownership scope.

Rules:

  - Each script MUST have a single, declared output directory.
  - All file creation, modification, or deletion MUST occur within this scope.
  - Writing to parent directories or unrelated paths is forbidden.
  - Temporary files MUST be created within the same confined scope.

Confidentiality:

  - Materialized intent, keys, or derived artifacts MUST NOT be written
    to shared, global, or user home directories.
  - Leakage of control-plane artifacts outside the confined scope
    is a critical contract violation.

Enforcement:

  - Scripts MUST fail if an output path resolves outside the allowed scope.
  - Silent redirection or fallback paths are forbidden.

Rationale:

  - Prevents accidental disclosure of sensitive material
  - Enables reliable cleanup and disaster recovery
  - Makes filesystem effects predictable and reviewable
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: Dump locality & inspectability
-------------------------------------------------------------------------------

All compiled dumps MUST be emitted into a canonical, inspectable location.

Rules:

  - plan.tsv, alloc.tsv, and keys.tsv MUST be written to the same directory
    as the compiler scripts.
  - Dump locations MUST NOT depend on invocation context.
  - Dump emission MUST be atomic and overwrite previous dumps.

Observability:

  - Dump files MUST be discoverable without prior knowledge of execution context.
  - Inspecting dumps MUST NOT require guessing or searching the filesystem.

Rationale:

  - Dumps are authoritative database snapshots
  - Their location is part of the contract
  - Inspectability is a correctness requirement, not a convenience
-------------------------------------------------------------------------------


-------------------------------------------------------------------------------
CONTRACT: License & reuse
-------------------------------------------------------------------------------

This contract text is licensed for use, reuse, and adaptation under the
following conditions:

  - Attribution to the original author is required
  - Modifications MUST be clearly documented
  - Derived contracts MUST preserve or strengthen invariants
  - Misrepresentation of modified contracts as original is forbidden

This license applies to the contract text itself,
independent of any code governed by it.

Use of this contract implies acceptance of its terms.
-------------------------------------------------------------------------------


===============================================================================
End of contracts.inc
===============================================================================
