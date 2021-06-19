# Working out Authentication between RAS and the FHIR API

This repository exists to enable collaboration between RAS and the dbGaP FHIR
API.

# Disclaimer

This repository is public for convenience. Its visibility should not be
construed as a promise that anyone will be able to depend on the documents in
the repository either as a source for information or as something to build on.
It may also not remain public.

# Setup, Installation, and Build

## Setup and Installation

### Setup

This has only ever been built on Linux (specifically, the Windows Linux
Subsystem running Ubuntu 18.04). You must install `npm` to run the installation.
You also need the JDK and `graphviz` (`dot`) to run `plantuml`
The simple method is to use:

    sudo apt install nodejs npm graphviz default-jdk

Google will give you many other options.

I use `npm` because it is the easiest way to install `prettier` and `bazel`.

### Installation

Clone the repository and `cd` to the checkout directory. Then execute

    npm install

## Building

### Build all

To rebuild, run

    npx bazelisk build "...:all"

The `*.png` files will be in `bazel-bin/uml/*.png`

### Update files in the image directory

To update and commit, run the following in an up-to-date repository

    bash update_repo_files.sh
    git commit -a

# Contributing

You should use `prettier` on Markdown files (like this one.) I haven't installed
pre-commit hooks since my editor runs it automatically and there are no linters
I know of for PlantUML. Use a Pull Request to enable us to comment on your
changes.

# Design Considerations

## How to include the passport in controlled-access requests

The passport (especially from dbGaP) is likely to eventually get too long for
any HTTP header maximum length set in the server unless those are set
ludicrously large. Therefore, authorization information either needs to be
reduced in size in some way or included in the body.

### Use big headers

There are currently 1700 studies in dbGaP. Let's triple that to 6000 studies.
Let's assume 3 consent groups on average. This means a dbGaP passport could
contain permission to access 9000 consent groups. The two consent groups in the
RAS example take 334 bytes in compact format. So, 167 bytes per. The "consent
name" is unbounded. So call that 300 bytes per. That puts the header size at
2.7MB. With more optimistic assumptions: 4000 studies, 2 consent groups, 200
bytes per group, and an individual only has access to half the study/consent
group combinations we get 800KB headers.

It is likely that servers upstream from our FHIR server (rate control, load
balancing) that are not under our control cannot be configured with headers this
large.

### Reduced-size auth

The client does a special `POST` to the server in order to receive a
reduced-size bearer token. The server stores the original passport and retrieves
it using information encoded in the special bearer token. After this, the client
can use all FHIR features the server supports. I think this will mirror the way
other OAuth-based systems work - with a small bearer token passed in the header
of each request.

We could make this a `PUT` to the server if we guarantee idempotence (include a
hash in the returned token and look up the hash.)

Statefulness would introduce a number of costs - maintaining the database,
ensuring timely invalidation, flushing the database, and cleaning out old data.

Really, RAS should include the option of such a "compressed" passport. Anyone
can go to the RAS server and retrieve a passport a compressed auth token. You
can also exchange that compressed token for one which corresponds to a passport
with reduced privileges.

Since we don't need to work with OAuth etc, our returned token can avoid
JOSE/JWT. But we'll use it anyway. In a few minutes of Googling I don't see any
good alternatives. (See ["Why I chose JWT"](#why-i-choose-jwt-for-our-tokens)
for more details.) So, I'll stick with the devil I know; I'll use JWT but limit
the algorithm to RSA and limit the header to a fixed size (to give attackers
less room for creative JSON stuffing).

#### Stateless option

Since we are only interested in what consent groups the user can see, we could
conceivably be stateless. Encoding 9000 consent groups takes 9000 bits or 1125
bytes. This expands to 1500 bytes under base64 wrapping (2000 bytes since most
token formats require us to wrap it twice.) However, in most circumstances most
of those bits are 0 and when they aren't we'd expect them mostly to be 1 (if
someone has access to most of the consent groups, they probably have access to
almost all of them.) So, Golomb coding should reduce the size substantially.

Here's a basic data structure:

    num_consent_groups  varint
    num_groups_with_access varint
    consent_group_list_update_time varint
    has_access golomb_compressed_bit_vector

We assume that the expiration date etc are in the standard JWT claims in the
wrapper.

One problem will be distributing an up-to-date list of the consent groups
in-order in such a way that adding a consent group doesn't accidentally give
access to the wrong group. I think we can solve that by having the consent group
list be in the database (with a sort order that is part of the consent group
list data e.g. each group has both an id and a sort order index). When the list
is updated, the code treats this as invalidating all the keys requiring the
passports to be re-submitted.

We need to be careful to obey the standard for how long our token can last to
allow for various validation changes (for example RAS could invalidate their old
signing key) and early rejection of the token.

### Auth in body

There is a special field in the body of the request to hold authorization bearer
tokens. One could use either `Resource.meta.tag` with a tag name of
`Http-Authorization` or an extension. The tag could have a system
`https://auth.nih.gov/docs/RAS/` and the `code` field could be the passport

The simplest way to include this is to require all controlled-access requests to
be batch `POST`. However, it is possible to include bodies with `GET` requests
and if they are accessible in the `AuthorizationInterceptor`, we could do
controlled-access with Auth-in-body and mostly normal requests.

### Comparison

The best in each row is styled as code.

| Category                             | Reduced Size | Auth in body | Big Headers |
| ------------------------------------ | ------------ | ------------ | ----------- |
| Stateful protocol?                   | Yes          | `No`         | `No`        |
| Data transmission?                   | `Normal`     | Large        | Large       |
| Time to verify token authenticity    | `Small`      | Medium       | Medium      |
| FHIR can be used as normal           | `Yes`        | No           | `Yes`       |
| Ease of implementation               | Low          | Medium       | `High`      |
| Ease of use                          | Medium       | Low          | `High`      |
| Risk of future breakage              | `Low`        | `Low`        | High        |
| Risk of implementation impossibility | `Low`        | `Low`        | High        |

### Decision

I choose the "Reduced Size" option.

I eliminate the "Big Headers" option for now because I think it is likely that
we won't be able to set the headers large enough in upstream servers. For
example, Google says nginx (used by our front-end controller) supports a maximum
length of 8K ... which is only 1% of the optimistic calculation above.

I eliminate the Auth-in-body option because it requires odd use of FHIR. It
seems more natural to allow implementers of apps that will use more than one
FHIR server to use the same FHIR access code with them and only have an
additional step at the beginning of ours to shrink the passport into something
of usable size. Since I also think that RAS ought to give tokens of usable size,
the "Reduced Size" option is more in-line with how I perceive RAS will develop
in the future.

# Security

## <span id="why-i-choose-jwt-for-our-tokens">Why I choose JWT for our tokens</span>

[An article on JWT alternatives from December 2018](https://wesleyhill.co.uk/p/alternatives-to-jwt-tokens/)
lists 3: PASETO, Macaroons, and Branca.
[Another article from April 2020](https://www.scottbrady91.com/JOSE/Alternatives-to-JWTs)
covers Fernet, Branca, and PASETO. None look like a clear winner. PASETO is the
most promising and it
[has similar criticisms to JWT](https://mailarchive.ietf.org/arch/msg/jose/sz6XzHkVP2eWip_OiV5OkPggWWA/).

### Branca

Branca's site got flagged by my antivirus so I eliminated it since security
problems are not a promising development for a security protocol. Even if that
is just a transient issue, it looks like Branca is only for internal systems
using symmetric encryption not for our application.

### Macaroons

Macaroons has stalled development. The last commit to
[`jmacaroons`](https://github.com/nitram509/jmacaroons/) was two years ago.
There are 10 open `dependabot` pull requests to fix unsafe dependencies which
date back years.

### PASETO

PASETO's last commit was less than a month ago, so someone still loves it. It
was presented at Defcon 26 by someone who was concerned with the security
implications of bad developer UI. However, it conceivably could have the same
problems with switching the algorithm to symmetric that JWT does.

## JWT Testing

I realized, looking at the JWTs that security software frequently has
implementation bugs and we should go the extra mile and have our own external
test suite for our JWT-using tokens that checks for the problems we're solving
in our software and some of the ones JWT library ought to be solving.

- Check for bad algorithms (NONE, not the RSA256 algorithm)
- Check for signing using a different key
- Check for big and/or malformed JSON payloads. Maybe we don't parse JSON for
  the JWTs we produce. Just string-compare the headers to a set of fixed headers
  and the payloads have minimal keys with one custom key that contains a
  protobuf message with our real payload structure and a second telling what the
  schema of that message is.

# Testing

## Mock RAS

In our dev environment, we chould have a Mock RAS for end-to-end functional
testing of our auth\*. This will allow us to test edge cases in the auth (like
invalidating the keys etc.) The dev deployment of the server will have its
configuration values set to the Mock RAS then we can run tests by configuring
the Mock RAS in different ways and the passing the values to the dev-deployed
server.
