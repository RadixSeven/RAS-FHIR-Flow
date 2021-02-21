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
The simple method is to use:

    sudo apt install nodejs npm

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
