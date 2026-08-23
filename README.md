# own-the-machine-tools

The review machinery for the [own-the-machine](https://github.com/ownthemachine/own-the-machine)
draft EU Regulation: the adversarial gate runner, the six gate prompts and
the mechanical linter. Split out so the law repository stays a civic
artefact (text, evidence, governance and the ledger of its own evolution)
while the workshop lives here.

This is machinery, not policy. The normative documents (GOVERNANCE.md,
DRAFTING-RULES.md, the constraints table) live with the law; the prompts
here enforce them and cite them by path. Review OUTPUTS also live with the
law, under pipeline/reviews/, because a verdict on a statute is part of the
statute's history, not of the tooling.

## Use

    cp .env.example .env && $EDITOR .env     # REQUESTY_API_KEY; .env is gitignored
    python3 lint-legislation.py              # run from the law repo root
    ./review.sh <bundle.md> <out.md> prompts/<gate>.md

Gate order and model-tier guidance: pipeline/README.md in the law repo.

## Where the review runs, and why it is in the EU

The gate runs on an EU-hosted, zero-retention endpoint by default. That is
not decoration. A campaign arguing about European ownership of automated
capital should not send its own drafts through a jurisdiction it is arguing
about, and a draft Regulation is unpublished legal text until it is filed.

    REVIEW_BASE_URL    https://router.eu.requesty.ai/v1
    REVIEW_MODEL       vertex/gemini-3.7-flash@eu
    REVIEW_REQUIRE_EU  1

The runner does not take the routing on trust. Before spending a token it
reads the router's own model metadata and refuses to start unless that model
is reported as `geolocation: eu`, `data_retention_days: 0` and
`data_used_for_training: false`. What it read is then stamped into the review
record, so every verdict in the law repository carries the evidence for the
claim rather than the claim:

    > Reviewer: `vertex/gemini-3.7-flash@eu` · router router.eu.requesty.ai ·
    > geolocation eu · retention 0d · trained-on false · lab google

Set `REVIEW_REQUIRE_EU=0` to use another router, for instance the OpenRouter
setup this repository used until 23 August 2026. It still works, and the
provenance line then simply names the router and claims nothing about
jurisdiction, because nothing was verified.

**EU-hosted is not EU-made, and the two should not be blurred.** The models
above are built by American laboratories and run on European infrastructure
under zero retention. Of the models this endpoint offers, only Mistral's are
from a European laboratory. Both facts belong in the record.

## Disclosure

Reviews are run adversarially by AI under the editor's responsibility, and
every verdict is committed to the law repository, failed rounds included.
This repo exists so that claim is inspectable, not decorative.

Licence: MIT. Reuse for your own legislation welcome; the prompts are the
interesting part.
