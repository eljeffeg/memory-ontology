# Bitemporal cases

The shapes check that a record is well formed. These cases check an answer:
which beliefs hold at a valid time, as known at a recorded time.

| File | Contents |
|---|---|
| `records.ttl` | Seventeen beliefs and the records that close them. It passes the temporal and memory shapes. |
| `cases.ttl` | Forty-one cases. Each gives a valid time, an optional recorded-time cut, and the beliefs that must be returned. Three also give the valid-time end a belief must report. |
| `held.rq` | The query under test. It reads ends only from closing records, as "Closing a record" in the top-level README describes. |
| `expected.rq` | Lists what each case expects, for the runner to compare. |

`tests/run.sh` runs both queries with Jena's `arq` and compares them case by
case. It then runs a control: `held.rq` with the two filters marked
`# the cut sees the closing record` removed. That query reads a close as soon as
it exists, whenever it was recorded, and the cases must catch it.

## What the cases cover

- Half-open valid intervals: the start is inclusive and the end exclusive.
- A recorded-time cut that is inclusive, for records and for closing records.
- A close recorded after the end it names, asked on both sides of the cut.
- A close recorded before the end it names.
- A correction with a replacement and a correction with none.
- A record that closes both clocks.
- A belief wrongly corrected and then asserted again as a new record.
- Two closing records on one belief: the earliest end wins, whichever was
  recorded first.
- Two beliefs about the same subject and predicate, held together.

## How the records are written

A close that has a successor is the successor belief: it carries
`temporal:supersedes` and `temporal:closes`, and its `temporal:validFrom` is the
earlier belief's end. A close with no successor is a `memory:Retraction`, typed
`temporal:Closure`, that reifies no triple. When it closes valid time, its `temporal:validFrom` is the
end. When it closes only recorded time, its `temporal:validFrom` repeats the
belief's start, because a correction names no valid-time end.

The records are memory records so that a close with no successor can be a
retraction. No record here carries a stored `temporal:validUntil` or
`temporal:recordedUntil`, and `held.rq` reads neither.

## Adding a case

Add a `vec:Case` to `cases.ttl` with a label, `vec:validAt`, and the beliefs it
expects in `vec:expect`. Leave `vec:expect` out when nothing should hold. Add
`vec:recordedAsOf` for a knowledge cut, and `vec:expectEnd` or `vec:expectNoEnd`
to check a reported end. If the case needs new records, add them to
`records.ttl` and correct the expectations of any later case they now appear in.

## Source

The cases are translated from `conformance/temporal/vectors-v2.json` in
[ontomark](https://github.com/DreamLab-AI/ontomark) at release 0.10.0, where
the same answers are checked against a second implementation. There a close is
a separate record that reifies nothing; here it is a superseding record. The
answers are the same.
