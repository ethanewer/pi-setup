#!/usr/bin/env python3
"""Author a synthetic multi-topic text corpus for the quoin-vellum task.

Each generated document is a stream of words drawn mostly from one of K latent
topics plus a small fraction of cross-topic noise and topic-neutral common
words. The latent topics are recoverable: a well-trained gensim topic model
separates them cleanly (high c_v coherence, high topic-word purity), while a
degenerate, badly-parameterised or wrong-topic-count model does not.

This generator is authored by the benchmark maintainers; it is NOT part of any
upstream source tree. It exists only so the corpus text shipped with the task
can be regenerated deterministically from a seed.

Usage:
  python3 gen_corpus.py <outdir> <domain1,domain2,...> [seed] [n_docs]
Writes <outdir>/docs.txt (one document per line) and <outdir>/keys.json
({topics, common, labels}) -- keys.json is for the verifier's ground truth and
is NOT given to the agent.
"""
import json
import os
import random
import sys

DOMAINS = {
    "astronomy": ["star", "planet", "galaxy", "nebula", "comet", "telescope",
                  "cosmos", "asteroid", "constellation", "orbit", "lunar",
                  "solar", "meteor", "supernova", "quasar", "redshift",
                  "pulsar", "exoplanet", "gravity"],
    "ocean": ["wave", "beach", "ocean", "tide", "sand", "surf", "shore",
              "current", "drift", "coast", "harbor", "reef", "lagoon",
              "estuary", "maritime", "seafoam", "shoreline", "atoll", "tidal"],
    "cooking": ["sauce", "spice", "chef", "oven", "bake", "flavor", "simmer",
                "ingredient", "dish", "recipe", "roast", "marinade", "herb",
                "broth", "caramelize", "seasoning", "saute", "mirepoix",
                "glaze", "umami"],
    "engine": ["engine", "fuel", "brake", "transmission", "piston", "gear",
               "clutch", "carburetor", "turbo", "cylinder", "valve",
               "crankshaft", "exhaust", "ignition", "radiator", "chassis",
               "axle", "differential", "muffler", "throttle"],
    "music": ["symphony", "orchestra", "violin", "piano", "melody", "tempo",
              "sonata", "chorus", "harmony", "rhythm", "cello", "overture",
              "concerto", "timbre", "legato", "forte", "adagio", "tremolo",
              "cadence", "vibrato"],
    "chemistry": ["electron", "proton", "neutron", "photon", "quantum",
                  "molecule", "atom", "particle", "valence", "isotope",
                  "fission", "catalyst", "binding", "enthalpy", "molar",
                  "stoichiometry", "lattice", "resonance", "electronegativity"],
    "botany": ["leaf", "root", "stem", "petal", "pollen", "chlorophyll",
               "seed", "fern", "blossom", "herb", "sprout", "photosynthesis",
               "stamen", "moss", "orchid", "bark", "sapling", "meadow",
               "tendril", "germinate"],
    "geology": ["granite", "basalt", "strata", "fault", "magma", "tectonic",
                "erosion", "sediment", "bedrock", "mantle", "fossil", "quartz",
                "igneous", "lava", "crust", "mineral", "shale", "geode", "mesa"],
    "aviation": ["wing", "fuselage", "propeller", "runway", "altitude",
                 "cockpit", "airspeed", "hangar", "taxiway", "throttle",
                 "rudder", "turbine", "glider", "landing", "airship", "pilot",
                 "elevator", "takeoff", "airstrip", "windsock"],
    "medicine": ["symptom", "diagnosis", "antibiotic", "vessel", "artery",
                 "vaccine", "dose", "clinic", "prescription", "surgeon",
                 "inflammation", "biopsy", "platelet", "cardiac", "screening",
                 "placebo", "metabolite", "aorta", "cytology", "anesthesia"],
}

COMMON = ["the", "light", "water", "heat", "time", "system", "new", "large",
          "small", "part", "state", "form", "level", "type", "number"]


def make(topics, n_docs=600, doc_len=120, common_frac=0.15, seed=0):
    random.seed(seed)
    pool = list(set(sum(topics, []) + COMMON))
    docs, labels = [], []
    for _ in range(n_docs):
        t = random.randrange(len(topics))
        words = []
        for _ in range(doc_len):
            r = random.random()
            if r < common_frac:
                words.append(random.choice(COMMON))
            else:
                words.append(random.choice(topics[t]))
        docs.append(words)
        labels.append(t)
    return docs, labels


def main():
    outdir = sys.argv[1]
    doms = [d.strip() for d in sys.argv[2].split(",") if d.strip()]
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 0
    n_docs = int(sys.argv[4]) if len(sys.argv) > 4 else 600
    topics = [DOMAINS[d] for d in doms]
    docs, labels = make(topics, n_docs=n_docs, seed=seed)
    os.makedirs(outdir, exist_ok=True)
    with open(os.path.join(outdir, "docs.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(" ".join(d) for d in docs) + "\n")
    with open(os.path.join(outdir, "keys.json"), "w", encoding="utf-8") as f:
        json.dump({"topics": topics, "common": COMMON, "labels": labels}, f)
    print(f"wrote {outdir}/docs.txt ({len(docs)} docs) keys.json")


if __name__ == "__main__":
    main()
