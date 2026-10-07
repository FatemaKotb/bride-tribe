# Bridal Party Coordination App: Backend Contract

This contract defines everything the UI can read and do. It's based on the requirements (BR-01 to BR-34) and the ERD.

The UI makes no decisions. It renders what the backend returns and calls the functions the backend tells it to call.

---

## 1. Conventions

### Transport
- Every call is `POST /rpc/<function_name>` with a JSON body. This maps directly to Postgres functions behind PostgREST (Supabase), or to any RPC-style backend.
- The caller is identified by their Supabase session, linked to a member by `sign_in`. Every function acts as the current member (`me`). No function accepts a member ID for "who is doing this."
- Every function except `list_members_for_login` and `sign_in` requires a session and returns `NOT_SIGNED_IN` without one.
- All times use the wedding's local time zone (Africa/Cairo). Times of day are sent as `"HH:MM"`.

### Response envelope
Every call returns one of these:

```json
{ "data": { ... } }
```

```json
{ "error": { "code": "CAR_FULL", "message": "Sara's car has no free seats." } }
```

`message` is always written for the end user. The UI shows it as is, in a toast or under the form.

### Shared shapes

**Row:** used by every list.

```json
{
  "id": "uuid",
  "emoji": "📿",
  "title": "Perfume",
  "subtitle": "In: Blue bag · Packed",
  "badges": [{ "label": "Shared", "tone": "neutral" }],
  "open": { "detail": "item", "id": "uuid" },
  "actions": [ Action, ... ]
}
```

- `tone` is one of `neutral`, `success`, `warning`, `danger`. The UI maps each tone to a color.
- `open` is optional. If present, tapping the row opens the detail view it names.

**Action:** a button. The backend includes only the actions the member is allowed to use right now.

```json
{
  "id": "claim",
  "label": "Claim",
  "style": "primary",
  "confirm": "Release your claim on the giveaways?",
  "call": { "function": "claim_item", "args": { "item_id": "uuid" } },
  "form": null
}
```

- `style` is one of `primary`, `secondary`, `danger`.
- `confirm` is optional. If present, the UI asks for confirmation with this text before calling.
- An action has either `call` or `form`, never both:
  - `call`: the UI calls the function with the args as given.
  - `form`: `{ "name": "cargo_request", "context": { "car_id": "uuid" } }`. The UI fetches `get_form` with that name and context, shows the form, and submits it.

After any successful action, the UI reloads the current screen.

**Filter:** used by every list.

```json
{
  "key": "type",
  "label": "Type",
  "multi": false,
  "options": [
    { "value": "personal", "label": "Personal" },
    { "value": "claimable", "label": "Claimable" }
  ],
  "selected": ["claimable"]
}
```

**List response:** returned by every list endpoint.

```json
{
  "title": "Items",
  "filters": [ Filter, ... ],
  "rows": [ Row, ... ],
  "empty_message": "No items match these filters.",
  "actions": [ Action, ... ]
}
```

The top-level `actions` are screen buttons, such as "Add item."

**Detail response:** returned by every detail endpoint.

```json
{
  "emoji": "🚗",
  "title": "Sara's car",
  "subtitle": "To the hotel",
  "sections": [
    { "title": "Details", "fields": [{ "label": "Leaves", "value": "9:00–10:30" }] },
    { "title": "Passengers", "rows": [ Row, ... ], "empty_message": "No passengers yet." }
  ],
  "actions": [ Action, ... ]
}
```

A section has either `fields` (label and value pairs) or `rows`.

---

## 2. Sign-In (BR-03, BR-03a)

### `list_members_for_login()`
The only read that works without a session. Returns names and roles only.

```json
{
  "members": [
    { "id": "uuid", "name": "Sara", "role_label": "Bridesmaid" }
  ]
}
```

The UI shows the list. Tapping a name shows the confirmation: "You're **Sara** (Bridesmaid)?" with "Yes, that's me" (calls `sign_in`) and "No, go back."

### `sign_in(member_id)`
Before calling this, the UI starts a Supabase anonymous session (`supabase.auth.signInAnonymously()`), which the Supabase client stores on the phone and sends with every call. `sign_in` then links that session to the chosen member.

```json
{ "me": { "id": "uuid", "name": "Sara", "role_label": "Bridesmaid" } }
```

Errors: `UNKNOWN_MEMBER`.

### `sign_out()`
Unlinks the session from the member. The "Not Sara? Switch" link calls this, then returns to the name list.

---

## 3. Read Endpoints

### `get_home()`
Backs the home screen (BR-26, BR-27, BR-34).

**Returns:**
```json
{
  "me": { "name": "Sara", "role_label": "Bridesmaid" },
  "my_status": {
    "value": "doing_makeup",
    "label": "Doing makeup",
    "updated": "12 min ago",
    "options": [{ "value": "at_home", "label": "At home", "emoji": "🏠" }, ...]
  },
  "attention": [ Row, ... ],
  "status_board": [ Row, ... ]
}
```

- **`me`** and **`my_status`:** the UI shows them at the top of every screen, as "Sara · Doing makeup" with a "Not Sara? Switch" link. Choosing an option calls `set_status`.
- **`attention`:** pending requests where I'm the responder, and cancellations that affected me since `attention_cleared_at`, including passengers or cargo leaving my car. Pending rows carry Accept and Decline actions. If any cancellation rows exist, the last row is a "Got it" action that calls `clear_attention`.
- **`status_board`:** one row per member. For example, title "Sara (Bridesmaid)", subtitle "Doing makeup · 12 min ago". Sorted by role, then name.

`get_home` has no side effects. Refreshing it never hides anything.

### `list_items(filters)`
Backs the Items list, containers, and vendors (BR-07a, BR-09a, BR-32).

**Filters:**

| Key | Options | Default |
|---|---|---|
| `owner` | `mine`, `shared` | `mine` |
| `kind` | `item`, `container` | both |
| `type` | `personal`, `claimable` | both |
| `packed` | `packed`, `not_packed` | both |
| `vendor` | `has_vendor` | off |
| `container` | each of my containers, plus `none` | all |
| `tag` | every tag in use | all |

**Behavior:**
- **`owner = mine`:** my items, items I've claimed, and my containers. Each row shows its container in the subtitle (BR-11a).
- **`owner = shared`:** one row per `group_id` for shared personal items, with members who have it in the subtitle and either an "Add to my list" action or an "On your list" badge (BR-07a). Also one row per shared claimable item, with "Claimed by Sara" or "Unclaimed."
- **`vendor = has_vendor`:** only items with vendor details, sorted by `expected_time`. The subtitle reads "Photographer · 5:00 pm · 2,000 EGP" and a badge shows the claimer or "Unclaimed" (BR-32).
- Screen action: "Add item" (form `item`) and "Add bag or box" (form `container`).

**Row actions:**

| Action | When shown | Calls |
|---|---|---|
| Add to my list | Shared personal group I don't have | form `item` with `{ "copy_of": id }` |
| Claim | Unclaimed claimable item | `claim_item` |
| Release | Claimable item I claimed | `release_claim` (with confirm) |
| Mark packed / Mark unpacked | Items I own or claimed, my containers | `set_packed` |
| Move to bag | My items and claimed items not in a container | form `move_to_container` |
| Remove from bag | Items in one of my containers | `move_to_container` with `container_id: null` |
| Edit | My items and containers, and any item with vendor details | form `item` or `container` |
| Delete | My items and containers | `delete_item` (with confirm) |

### `get_item(item_id)`
Detail view for one item or container.

- **Item:** details (description, quantity, tags, visibility, type, claimer), vendor details if any, and its cargo requests.
- **Container:** its contents as rows, and its cargo requests.
- Actions are the same as the row actions above.

### `list_cars(filters)`
Backs the Cars list (BR-18).

| Key | Options | Default |
|---|---|---|
| `trip` | `to_hotel`, `hotel_to_venue`, `return_home` | `to_hotel` |

**Rows:** one per active (not withdrawn) car on the trip. For example, title "Sara's car", subtitle "Maadi · leaves 9:00–10:30 · 2 of 4 seats taken". Badges show "Full" (warning) and "Trunk 50%". Tapping opens `get_car`.

**Screen action:** "I'm coming with my car" (form `car` with `{ "trip": ... }`). Shown only if I have no car on this trip.

### `get_car(car_id)`
Car detail.

**Sections:**
- **Details:** home area or drop-off areas, departure window, travel times, trunk space.
- **Stops:** each labeled "For myself" or "For the bride."
- **Notes:** visible to everyone (BR-16).
- **Passengers:** confirmed passengers. My own row has a "Leave this car" action.
- **Cargo:** confirmed cargo. Rows for my cargo have a "Take it out of this car" action.

**Actions:**

| Action | When shown | Calls |
|---|---|---|
| Ask to ride | Not my car, seats free, I'm not confirmed in a car on this trip, no pending Ask from me to this car | `send_request` |
| Ask to carry an item | Not my car, and I have eligible cargo | form `cargo_request` |
| Offer a seat | My car, seats free | form `passenger_offer` |
| Offer to carry an item | My car | form `cargo_offer` |
| Edit | My car | form `car` |
| Withdraw | My car | `withdraw_car` (with confirm) |

### `list_requests(filters)`
Backs the Requests list (BR-25).

| Key | Options | Default |
|---|---|---|
| `direction` | `sent`, `received` | both |
| `state` | `pending`, `confirmed`, `declined`, `cancelled` | `pending` |
| `kind` | `passenger`, `cargo` | both |

**Rows:** for example, title "Ride in Sara's car", subtitle "To the hotel · You asked · Pending". For cargo: "🎁 Giveaways in Sara's car · Pickup: bride's home, ready 10:00."

**Row actions:** Accept and Decline when I'm the responder and the request is pending. Cancel when I sent it and it's pending. "Leave this car" or "Take it out of this car" when the request is confirmed and I'm the passenger or the cargo's owner.

### `get_form(name, context)`
Returns a form schema. See Section 5.

---

## 4. Write Functions

Every write function checks all its rules in one transaction. If any rule fails, nothing changes and the function returns the listed error.

### Status

**`set_status(status)`** (BR-25, BR-26)
- Sets my status and `status_updated_at`.
- Errors: `INVALID_STATUS`.

**`clear_attention()`** (BR-34)
- Sets my `attention_cleared_at` to now, removing cancellation rows from my home screen. Pending requests stay until I respond.

### Items and containers

**`create_item(fields)`** (BR-04 to BR-07)
- Inputs: `name`, `emoji`, `description`, `quantity`, `tags`, `visibility`, `type`, optional `vendor` (object), optional `copy_of` (item ID).
- If `copy_of` is set, the new item takes the source's `group_id`. Otherwise it gets a new `group_id`.
- Rules:
  - `type = claimable` forces `visibility = shared`.
  - `vendor` is allowed only when `type = claimable`.
  - `copy_of` must be a shared personal item, and I must not already have an item in that group.
- Errors: `NAME_REQUIRED`, `VENDOR_NOT_ALLOWED`, `COPY_NOT_ALLOWED`, `ALREADY_ON_YOUR_LIST`.

**`update_item(item_id, fields)`**
- The owner can change any field. Any member can change `vendor` (BR-30).
- Changing `type` from claimable to personal is allowed only if the item is unclaimed and has no vendor details.
- Errors: `NOT_ALLOWED`, `VENDOR_NOT_ALLOWED`, `TYPE_CHANGE_NOT_ALLOWED`.

**`create_container(name, emoji)`** (BR-10)
- Creates an `ITEM` row with `kind = container`, owned by me.

**`delete_item(item_id)`**
- Owner only.
- Deleting an item cancels its pending and confirmed cargo requests (`auto`).
- Deleting a container moves its contents out (`parent_id = null`) and cancels the container's cargo requests (`auto`).
- Deleting the original of a group leaves the group intact through its copies (BR-07b).
- Errors: `NOT_ALLOWED`.

**`claim_item(item_id)`** (BR-08)
- The item must be claimable and unclaimed.
- Errors: `NOT_CLAIMABLE`, `ALREADY_CLAIMED`.

**`release_claim(item_id)`** (BR-08)
- Only the claimer.
- Effects: removes the item from my container and cancels its pending and confirmed cargo requests (`auto`).
- Errors: `NOT_ALLOWED`.

**`set_packed(item_id, packed)`** (BR-09)
- The owner of a personal item or container, or the claimer of a claimable item.
- Errors: `NOT_ALLOWED`.

**`move_to_container(item_id, container_id)`** (BR-10, BR-11)
- `container_id` can be `null` to remove the item from its container.
- Rules: the target is my container, and the item is mine or claimed by me. A container can't go inside a container.
- Effects: moving an item into a container cancels its own pending and confirmed cargo requests (`auto`).
- Errors: `NOT_ALLOWED`, `NOT_A_CONTAINER`, `NO_NESTING`.

### Cars

**`register_car(trip, fields)`** (BR-13 to BR-15)
- Inputs depend on the trip (see the `car` form).
- Rules: one car per member per trip; `departure_earliest <= departure_latest`; trip-specific fields only on their trip; "other" text required when the area is `other`.
- Errors: `ALREADY_HAS_CAR`, `INVALID_WINDOW`, `FIELD_NOT_ALLOWED`, `OTHER_AREA_REQUIRED`.

**`update_car(car_id, fields)`**
- Owner only. The trip can't change.
- `seats` can't go below the current number of confirmed passengers.
- Errors: `NOT_ALLOWED`, `SEATS_BELOW_CONFIRMED`, plus the `register_car` errors.

**`withdraw_car(car_id)`** (BR-19)
- Owner only. Sets `withdrawn_at` and cancels all the car's pending and confirmed requests (`car_withdrawn`).
- Errors: `NOT_ALLOWED`.

### Requests

**`send_request(car_id, kind, direction, subject, pickup)`** (BR-20, BR-22 to BR-24)
- `subject` is `passenger_id` for passenger requests, or `item_id` for cargo.
- `pickup` (cargo only): `pickup_type`, `pickup_address` (custom only), `ready_at` (optional).
- **Ask:** the passenger must be me, or the cargo's owner must be me. The car must not be mine.
- **Offer:** the car must be mine. The passenger, or the cargo's owner, must not be me.
- Rules:
  - the car is active,
  - for passengers, the car has a free seat,
  - the subject isn't already confirmed in a car on this trip,
  - there's no pending request for the same subject and car,
  - cargo is claimed if claimable, not inside a container, and `vendor_address` is used only when the item has a vendor address.
- Errors: `CAR_WITHDRAWN`, `CAR_FULL`, `OWN_CAR`, `ALREADY_CONFIRMED_ON_TRIP`, `DUPLICATE_REQUEST`, `NOT_YOUR_CARGO`, `UNCLAIMED_CARGO`, `CARGO_IN_CONTAINER`, `PICKUP_INVALID`.

**`respond_to_request(request_id, accept)`** (BR-21 to BR-23)
- Only the responder, and only while pending.
- On accept, the function re-checks seats and the one-car-per-trip rule, then confirms. Effects:
  - cancels the subject's other pending requests on the same trip (`auto`), and
  - if this filled the car's last seat, cancels the car's remaining pending passenger requests (`auto`).
- On decline, sets the request to `declined`.
- Errors: `NOT_ALLOWED`, `NOT_PENDING`, `CAR_FULL`, `ALREADY_CONFIRMED_ON_TRIP`.

**`cancel_request(request_id)`** (BR-21)
- Only the sender, and only while pending. Sets `cancel_reason = by_sender`.
- Errors: `NOT_ALLOWED`, `NOT_PENDING`.

**`leave_car(request_id)`** (BR-21)
- Only the passenger, or the cargo's owner, and only while confirmed. Sets `state = cancelled` and `cancel_reason = left_car`, freeing the seat.
- The car owner sees the change in "Needs your attention."
- Errors: `NOT_ALLOWED`, `NOT_CONFIRMED`.

---

## 5. Form Schemas

### Shape

```json
{
  "name": "car",
  "title": "I'm coming with my car",
  "context": { "trip": "to_hotel" },
  "fields": [ Field, ... ],
  "submit": { "function": "register_car", "label": "Save" }
}
```

**Field:**

```json
{
  "key": "home_area",
  "label": "Where do you live?",
  "type": "select",
  "required": true,
  "options": [{ "value": "maadi", "label": "Maadi" }, ...],
  "hint": null,
  "default": null,
  "value": null,
  "visible_if": { "field": "trip", "equals": "to_hotel" }
}
```

**Field types:** `text`, `textarea`, `number`, `emoji`, `tags`, `select`, `multiselect`, `time`, `toggle`, `group` (a fixed set of nested fields), and `list` (a repeatable group of nested fields, such as stops).

- `visible_if` is optional. A hidden field isn't submitted.
- `value` holds the current value when the form edits an existing record.
- On submit, the UI sends `context` plus the field values to `submit.function`.

### `item`
**Context:** none for a new item, `{ "item_id" }` to edit, or `{ "copy_of" }` to copy (fields are pre-filled from the source).

| Key | Type | Notes |
|---|---|---|
| `name` | text | Required |
| `emoji` | emoji | |
| `description` | textarea | |
| `quantity` | number | |
| `tags` | tags | Suggestions are the tags already in use |
| `type` | select | Personal or Claimable |
| `visibility` | select | Private or Shared. Visible only when `type = personal` |
| `vendor` | group | Visible only when `type = claimable`. Holds `vendor_name`, `service`, `phone`, `address`, `expected_time`, `amount_egp`, and `details` |

When a non-owner edits an item with vendor details, the backend returns only the `vendor` group.

### `container`
**Fields:** `name` (required) and `emoji`.

### `move_to_container`
**Context:** `{ "item_id" }`.
**Fields:** `container_id`, a select whose options are my containers only.

### `car`
**Context:** `{ "trip" }` for a new car, or `{ "car_id" }` to edit.

| Key | Type | Visible when | Notes |
|---|---|---|---|
| `seats` | number | Always | Required |
| `departure_earliest` | time | Always | Hint: *"Only choose times you're truly fine with. The bride may pick any time in this window."* |
| `departure_latest` | time | Always | Same hint |
| `home_area` | select | `to_hotel` | Required |
| `home_area_other` | text | `home_area = other` | Required |
| `minutes_to_bride` | number | `to_hotel` | Hint: *"Check Google Maps for the estimate."* |
| `minutes_to_hotel` | number | `to_hotel` | Same hint |
| `stops` | list | `to_hotel` | Each stop has `description` (text) and `purpose` (select: For myself or For the bride) |
| `dropoff_areas` | multiselect | `return_home` | Labeled "Areas I can drop people off in" |
| `dropoff_area_other` | text | `dropoff_areas` includes `other` | Required |
| `trunk_percent` | select | Always | 0%, 25%, 50%, 75%, or 100% |
| `notes` | textarea | Always | Hint: *"Everyone can read this."* |

The departure-time labels change by trip: "leave home" for To the hotel, "leave the hotel" for Hotel to venue, and "leave the venue" for Return home.

### `passenger_offer`
**Context:** `{ "car_id" }`.
**Fields:** `passenger_id`, a select listing only members who can still be offered a seat: not me, not confirmed on this trip, and no pending request with this car.

### `cargo_request` and `cargo_offer`
**Context:** `{ "car_id" }`.

| Key | Type | Notes |
|---|---|---|
| `item_id` | select | **Request:** my eligible items and containers. **Offer:** other members' eligible items and containers. Eligible means claimed if claimable, not inside a container, and not confirmed on this trip |
| `pickup_type` | select | Bride's home, Vendor's address (shown only for items with a vendor address), or Custom |
| `pickup_address` | text | Visible when `pickup_type = custom`. Required |
| `ready_at` | time | Optional |

---

## 6. Error Codes

| Code | Example message |
|---|---|
| `NOT_SIGNED_IN` | Please pick your name to continue. |
| `UNKNOWN_MEMBER` | We couldn't find that name. |
| `NOT_ALLOWED` | You can't change this. |
| `NAME_REQUIRED` | Please give the item a name. |
| `VENDOR_NOT_ALLOWED` | Vendor details can only be added to claimable items. |
| `TYPE_CHANGE_NOT_ALLOWED` | Release the claim and remove the vendor details before making this personal. |
| `COPY_NOT_ALLOWED` | This item can't be copied. |
| `ALREADY_ON_YOUR_LIST` | This is already on your list. |
| `NOT_CLAIMABLE` | This item can't be claimed. |
| `ALREADY_CLAIMED` | Mai already claimed this. |
| `NOT_A_CONTAINER` | Pick a bag or box. |
| `NO_NESTING` | A bag can't go inside another bag. |
| `ALREADY_HAS_CAR` | You already have a car on this trip. |
| `INVALID_WINDOW` | The earliest time must be before the latest time. |
| `FIELD_NOT_ALLOWED` | This field doesn't apply to this trip. |
| `OTHER_AREA_REQUIRED` | Please type the area. |
| `SEATS_BELOW_CONFIRMED` | You already have 3 confirmed passengers. |
| `CAR_WITHDRAWN` | This car is no longer available. |
| `CAR_FULL` | Sara's car has no free seats. |
| `OWN_CAR` | That's your own car. |
| `ALREADY_CONFIRMED_ON_TRIP` | Nour already has a ride on this trip. |
| `DUPLICATE_REQUEST` | There's already a pending request for this. |
| `NOT_YOUR_CARGO` | You can only send your own items. |
| `UNCLAIMED_CARGO` | Someone needs to claim this item first. |
| `CARGO_IN_CONTAINER` | This item travels with its bag. Send the bag instead. |
| `PICKUP_INVALID` | Please choose a valid pickup location. |
| `NOT_PENDING` | This request has already been answered. |
| `NOT_CONFIRMED` | This ride isn't confirmed. |
| `INVALID_STATUS` | Please choose a status from the list. |

Messages use real names where relevant, such as the car owner or the claimer.
