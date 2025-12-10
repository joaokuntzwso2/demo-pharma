package pharma.authz

default allow = false

#
# Role detection from Scopes string
#

is_pharmacist {
    raw := input.Scopes                    # e.g. "[pharma_farmaceutico pharma_atendente]"
    contains(raw, "pharma_farmaceutico")
}

is_attendant {
    raw := input.Scopes
    contains(raw, "pharma_atendente")
}

#
# Very simple “controlled drug” detector in PT-BR
# One rule per keyword (OPA ORs them automatically)
#

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "tarja preta")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "medicamento controlado")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "medicação controlada")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "medicacao controlada")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "remédio controlado")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "remedio controlado")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "psicotrópico")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "psicotropico")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "benzodiazepínico")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "benzodiazepinico")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "opioide")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "opiáceo")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "opiaceo")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "substância controlada")
}

is_controlled_query {
    msg := lower(input.AI_MESSAGE)
    contains(msg, "substancia controlada")
}

#
# Authorization logic
#

# 1) Pharmacist can always call (anything)
allow {
    is_pharmacist
}

# 2) Attendant can call only if NOT controlled-drug content
allow {
    is_attendant
    not is_controlled_query
}
