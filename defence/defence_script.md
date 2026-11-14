# BA Defence: Talk Script and Q&A

Deck: `BA_Defence_Kurouski.pptx` · Talk: 5–7 minutes, English · Target pace: about 130 words a minute.

Square brackets are cues, not words to say. Times are cumulative.

---

## Part 1. Talk script

### Title slide [0:00 – 0:20]

Good afternoon. My name is Yury Kurouski, and I present the business analysis of my diploma project: a platform that helps web studios find local clients. It checks a business's website, drafts a better version with AI, and lets one studio contact that business, with a person approving every message. I will follow one thread: problem, goal, KPI, epic.

### Slide 1. Many sites need help; pitching them is slow [0:20 – 1:00]

[Point to the big number.]
Local businesses depend on their websites, and many of these sites are slow, hard to use and dated. This year automated tests found accessibility errors on almost 96 percent of the million most popular home pages.

For web studios these businesses are natural clients. But the first contact is expensive: research, an assessment and a mock-up for every prospect, and all of it is lost when nobody replies. Often several studios pitch the same business.

AI can now draft a better site cheaply, but it also invents facts, so full automation is not reliable.

### Slide 2. Goal, objectives, object and subject [1:00 – 1:40]

My goal is to help web studios win local clients with less manual work.

[Point to the objectives.]
There are five objectives: study today's process and tools; set goals, KPIs and scope; write the user stories; set the quality and legal rules; and plan how to verify the result.

The object is how studios find new clients. The subject is the part of that process that can be automated.

### Slide 3. Today every pitch is made by hand [1:40 – 2:25]

This is how a studio finds clients today. It is my model, built from the tools I compared and my working prototype; I did not interview studios.

[Walk along the boxes.]
Time and data are lost in four places. One: the site is judged by eye, or by tools that give a different score on each run. Two: each studio checks only its own records, so a "please stop" reaches just one studio. Three: the mock-up is drawn before anyone knows the business is interested. Four: the owner gets pitches from several studios.

So every prospect costs hours, even the ones who never reply.

### Slide 4. Analogs: no tool covers it all [2:25 – 3:05]

I compared one tool from each group that covers part of the job.

Apollo, which I tried myself, finds contacts and sends e-mail sequences. But it says nothing about the prospect's website, offers no exclusivity, and approving each e-mail is optional.

Lighthouse checks a website, but its scores change between runs, so one run is a weak basis for a price.

Clutch is a directory where the business has to start the search itself.

[Point to the dark box.]
So no tool connects site evidence, one studio per business, and approved outreach.

### Slide 5. Vision: leads backed by evidence [3:05 – 4:05]

My vision: the platform gives studios ready leads, backed by evidence.

[Point down one column.]
Each column reads top to bottom as one chain: a problem, the goal that answers it, the KPI that measures it, and the epic that delivers it.

Slow manual contact: an operator should need at most fifteen minutes per lead.
Site quality judged by eye: at least 95 percent of sites get the same result when checked again a day later.
Unreliable AI: at least 80 percent of generated pages pass the code checks first time.
Studios chasing the same business: zero businesses pitched twice.

[Point to the strip.]
In scope: the pipeline, studio accounts, the contact registry and purchase. Out of scope: e-mail sent by the platform, full websites and auctions.

### Slide 6. What we build and the key scenario [4:05 – 4:50]

The requirements form six epics. The pipeline already works: it finds businesses, checks their sites, generates a new design and lets a person approve the e-mail. Studio accounts, the contact registry and purchase are must-haves. The owner self-check is a should-have, and the market map is nice to have. Behind them are seventeen user stories; the twelve must-haves have testable acceptance criteria.

[Point to the steps.]
The key scenario: the operator finds hidden listings and pays a fixed price. The system grants the exclusive right exactly once, shows the business and generates the new design. And the operator approves the e-mail.

### Slide 7. Safe, fair and legal by design [4:50 – 5:35]

There are ten quality requirements with measurable targets; these four carry the most risk. No studio ever sees another studio's data. No business is sold to two studios, even under a hundred purchases at once. No e-mail leaves without a person's approval. And the screens meet accessibility level AA.

On the legal side, contacting businesses rests on legitimate interest under GDPR, and one "please stop" blocks every studio. E-mail rules for companies differ by country, so each market gets a legal check first. Owners who come to us themselves give consent, which they can withdraw.

### Slide 8. How it works and the top risks [5:35 – 6:30]

[Point to the centre of the diagram.]
Each studio has its own private account. The platform checks each website once and publishes hidden listings: type of business, district, check result and price, but no name or contacts. A studio buys the exclusive right to contact the business for a fixed period. Only then does it see the business and get the new design. A person approves the e-mail, which goes from the studio's own address.

[Point to the risks.]
The three biggest risks: too few studios buying, too much to build in the time, and e-mail law that differs by country.

Thank you. I am ready for your questions.

---

## Part 2. Answers to the committee's typical questions

Each answer opens with one short sentence; the rest is there if they ask for more. The backup slide to show is in brackets.

### 1. How did you make sure the problem is real and not made up?

**Short answer:** Public measurements show the website defects are widespread, my own trials showed that no existing tool closes the gap, and the time cost is a stated assumption that I will measure before the pilot.

- Website defects: accessibility errors on 95.9% of the top million home pages (WebAIM, 2026); only 43% of sites have good Core Web Vitals on mobile (Web Almanac 2024). These describe the web in general, not local businesses specifically, so I use them as context only.
- Tools: I tried Apollo with my own account, ran Lighthouse, and browsed Clutch. The gap in the comparison comes from those trials and the vendors' own pages (Backup A).
- Feasibility: the core pipeline already works as a single-operator prototype.
- Honest limit: I held no interviews, so the personas are constructed and the time a studio spends per lead is assumption A3. The K1 baseline will be timed on the manual process before the pilot, and no baseline is estimated without data.

### 2. How is your solution better than the analog already on the market?

**Short answer:** It is not a better Apollo; it combines three things no single tool links: evidence about the prospect's website, one studio per business, and outreach a person approves.

- Apollo: contacts and sequences, but no audit of the prospect's site, no exclusivity stated, and human approval is optional.
- Lighthouse: an audit, but its lab scores can change between runs. On the W3C inaccessible demo page it gave Performance 100 and Accessibility 50, so speed alone does not show that a site needs a redesign.
- Clutch: works only when the business starts the search, and studios pay for visibility, not for access to one business.
- On top of that it adds an opt-out shared by all studios, which none of them offers (Backup A).

### 3. Why exactly these KPIs, and how will you measure them?

**Short answer:** One KPI per problem, and each is measured from data the system already records.

| KPI | Target | How it is measured |
|---|---|---|
| K1 Operator time per lead | ≤ 15 min | Median time from buying the right to approving the e-mail, from dashboard timestamps |
| K2 Same audit result on re-run | ≥ 95% | Audit 20+ public sites twice, one day apart; compare the band and the price |
| K3 AI pages passing checks first time | ≥ 80% | Page-check results over 30+ generations |
| K4 Businesses pitched twice | 0 | Contact-registry query after the pilot and in the market simulation |

The targets are proposals to confirm in the pilot (Backup B). The fifth problem, data isolation, has no KPI; it is checked by requirement NFR3, an isolation test suite.

### 4. What stays outside the project, and why?

**Short answer:** Platform-sent e-mail, full websites and auctions, because each would add legal risk or needs a market that does not exist yet.

- E-mail from a platform domain: it would move the sender's reputation and the legal responsibility to the platform, and the law requires the real sender to be identifiable. Each studio sends from its own address.
- Full multi-page production websites: the prototype is a one-page MVP to start the conversation; building the real site is the studio's job.
- Auctions: they need many bidders, which a young market lacks; research on eBay shows sellers moved from auctions to posted prices for convenience. A fixed price comes first, and the auction is future work.
- Also out: data about private individuals, mobile apps, and payouts between studios.

### 5. Which stories are Must, and why? What will you drop if time runs short?

**Short answer:** The twelve stories of the pipeline, studio accounts, contact registry and purchase are Must, because without any one of them the business model does not work. If time runs short, the market map goes first, then the owner self-check.

- Must: US1–US7 and US10–US14. Without studio accounts there is only one studio; without the registry, exclusivity and the shared opt-out cannot be enforced; without purchase there is no revenue.
- Should: US8, the owner self-check (inbound flow). Could: US9, the market map.
- Won't (recorded as future work): auctions, owner-published sites, platform-sent e-mail.
- This follows constraint C1 (one developer, the diploma timeline) and risk R2 (Backup C).

### 6. What personal data does the system process, and on what legal basis?

**Short answer:** Only business contact details the business publishes itself, studio user accounts and consent records, with no data about private individuals. Outbound contact rests on legitimate interest, inbound contact on consent.

- Data: the e-mail, phone and address a business publishes. For a sole trader these identify a natural person, so GDPR applies.
- Outbound: GDPR Article 6(1)(f), legitimate interest, supported by Recital 47 and a balancing test. An objection under Article 21 blocks that business for every studio.
- Inbound: consent, stored with its time, text and source, and withdrawable at any time.
- Accounts and payments: the contract. Card data stays with the payment provider.
- ePrivacy Article 13 leaves the rules for companies to national law, so every target country gets a legal review first. Every e-mail names the sending studio and has an opt-out.
- Data minimisation and protection by design (Articles 5 and 25): identities stay hidden until purchase, and each studio's data is isolated. The controller roles and retention periods go into a Privacy Notice and a Data Processing Agreement (task REV-176).

### 7. What is the riskiest part of the project, and what are you doing about it?

**Short answer:** A thin market: the model works only if enough studios buy in the same area. That is why I test pricing in a simulation before launch and keep the auction for later.

- Start with large cities.
- US7, a deterministic market simulation, compares pricing rules on revenue, unsold share, buyer concentration and overpayment before any real money moves.
- Consider a price that falls while a lot stays unsold.
- The second risk is scope too large for the timeline: MoSCoW, with the pipeline, accounts, registry and purchase first. The third is that e-mail law differs by country: legal review per market plus the consent-based inbound flow (Backup D).

---

## Part 3. Other likely questions

**How is the price set?**
By code from the audit result, never by AI. Two businesses with identical audit results get identical prices (US5), and the rule is calibrated in the simulation.

**How do you stop the AI from inventing facts?**
The AI writes only the design and the wording. Metrics, contacts, prices and names come from deterministic code. Contacts go in as placeholders and are filled from verified data. Code checks every page before anyone sees it; a page that fails twice is not published. Numbers and names the original site does not contain are flagged to the operator, and a person approves every e-mail (US14, NFR6).

**Can a studio work out which business a hidden listing is and skip paying?**
Listings use coarse areas and score bands. A profile shared by fewer than k businesses is withheld, and listing requests are rate-limited, so scraping is blocked (risk R5, NFR9).

**Why should the audit be repeatable rather than complete?**
Because it sets the price. Automated accessibility tools cover at most half of the WCAG criteria (Vigo et al.), so the audit reports the violations it detected and never claims that a site conforms. What matters for a fair price is that the same site gets the same result.

**What exists today and what is only specified?**
The core pipeline works as a single-operator prototype: discovery, audit, AI prototype with code checks, review and e-mail. Studio accounts, the contact registry, purchase, the inbound flow and the market map are specified in this work and are the next to be built.

**Why didn't you interview studios?**
I did not hold any, and the thesis says so openly in the methods and in §1.1. Instead, the personas are constructed from the problem analysis, every statement without a source is marked as an assumption (A1–A3), and the pilot measures them, starting with the K1 baseline.

**How did you use AI in writing the thesis?**
As stated in the thesis: to structure the document, draft and edit the English text from my materials, find sources and check their bibliographic data, and write the code that draws the diagrams. I opened and checked every source; the goal, objectives and design decisions are mine.

---

## Delivery tips

- Rehearse with a timer twice. If you pass 6:30, shorten slides 5 and 7 first.
- Say numbers as words: "fifteen minutes", "ninety-five percent". Don't read out the codes; point to them if asked.
- If you don't know an answer, say what the thesis does cover and where: "That is outside the scope; section 2.3 lists what is out and why."
