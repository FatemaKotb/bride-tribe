# Bridal Party Coordination App: Business Requirements

**Scope:** Minimum viable product (MVP). Every requirement in this document is in scope for the MVP.
**Event:** A single wedding.

---

## 1. Core Concepts

| Concept | Description |
|---|---|
| **Member** | A person with an account and a role. |
| **Item** | Something a member needs to bring or handle. A shared claimable item can also hold vendor details. |
| **Container** | A bag or box that groups items and is handled as one unit. |
| **Trip** | One of the three planned journeys: To the hotel, Hotel to venue, or Return home. |
| **Car** | A ride a member offers on a specific trip. |
| **Request** | A proposal to place a passenger or cargo in a car. |

---

## 2. Roles and Permissions

**BR-01. Roles.** Each member has one of three roles: **Bride**, **Maid of Honor**, or **Bridesmaid**. Roles are labels only. They appear next to the member's name wherever names are shown, for example on the status board and in passenger lists ("Mai (MoH)"), and they don't affect permissions.

**BR-02. Equal permissions.** All roles have the same permissions. No member can assign, override, or remove another member's claim, ride, or cargo.

**BR-03. Accounts and sign-in.** Each member has one account, added in advance by the app's developer with the member's name and role. There is no sign-up and no password. To sign in:
- the member picks her name from the list of members,
- the app asks her to confirm, for example "You're **Sara** (Bridesmaid)?" with "Yes, that's me" and "No, go back," and
- the app remembers her on that phone, so she signs in only once.

**BR-03a. Current member always visible.** The signed-in member's name appears at the top of every screen next to her status, for example "Sara · Doing makeup," with a "Not Sara? Switch" link that signs her out and returns to the name list.

---

## 3. Items

**BR-04. Creating items.** A member can create an item with a **name**. The member can also add an **emoji icon**, a **description**, a **quantity**, and any number of free-form **tags** (for example "makeup" or "emergency kit"), but these are optional.

**BR-05. Visibility.** Each item has a visibility setting:
- **Private** items are visible only to the member who created them.
- **Shared** items are visible to all members.

**BR-06. Item type.** Each item has a type:
- **Personal** items are things every member needs their own copy of, such as a hair clip.
- **Claimable** items are things the group needs only one of, such as the giveaways. Exactly one member can claim a claimable item. Claimable items are always shared.

**BR-07. Adding to my list.** When a member views a shared personal item, they can choose **"Add to my list."** This opens the add-item form pre-filled with that item's details. The member can save it as is or edit it first. Either way, the result is a new item that belongs to them and stays **linked** to the item it was copied from.

**BR-07a. Grouping copies in the shared list.** The shared list shows **one row per original item**, not one row per copy. Each row:
- lists the members who have the item, for example "📿 Perfume: Rana, Sara, Mai," and
- shows **"Add to my list"** to members who don't have it yet, and **"On your list"** to members who do.

Editing a copy (for example, changing the brand) changes only that member's own item. It does not break the link or change the shared row. A copy that the member made private does not appear in the group.

**BR-07b. Deleting the original.** If the member who created the original item deletes it, the group stays in the shared list, anchored to the next copy, so the item doesn't disappear for everyone else.

**BR-08. Claiming.** Each shared claimable item shows its state as **Unclaimed** or **Claimed by [name]**. Claims work as follows:
- Any member can claim an unclaimed item.
- Only the member who claimed an item can release the claim.
- Releasing a claim removes the item from the member's container, if it is in one, and cancels any pending or confirmed cargo requests for it. Affected members see the cancellation in "Needs your attention" (BR-34).

**BR-09. Packing.** A member can mark their own items as **Packed**.

**BR-09a. Filtering items.** All items appear in one **Items** list, which can be filtered by:
- **Owner:** mine or shared
- **Type:** personal or claimable
- **Packed:** packed or not packed
- **Vendor details:** has vendor details or not
- **Container:** a specific bag or box, or not in a container
- **Tag:** any tag in use

Rules such as visibility, type, and claims are stored as fixed fields, not as tags, so the app can enforce them. Tags are free-form and carry no rules.

---

## 4. Containers

**BR-10. Creating containers.** Any member can create a bag or box. Using containers is optional, so members can leave items ungrouped. A container:
- belongs to the member who created it,
- can hold only that member's own items and the claimable items they have claimed, and
- is shared if it contains at least one shared item; otherwise it is private.

**BR-11. Containers as one unit.** When items are inside a container, the container is what gets packed and transported (through a cargo request). The items inside it follow along automatically. An item inside a container can't be sent as cargo on its own, and moving an item into a container cancels any pending or confirmed cargo requests for that item.

**BR-11a. Showing the container.** Wherever an item appears in a list, it shows the container it belongs to, for example "Perfume · In: Blue bag." Items that aren't in a container show nothing extra. In the grouped rows of the shared list (BR-07a), each member's copy can be in a different container, so the shared row doesn't show a container.

---

## 5. Trips

**BR-12. The three trips.** The app has three fixed trips, and each one is planned separately. Trips are labels only: they have no address or time in the app, and the bride sets times outside the app.

| Trip | From | To |
|---|---|---|
| **To the hotel** | Members' homes | Hotel |
| **Hotel to venue** | Hotel | Wedding venue |
| **Return home** | Venue | Members' homes |

The bridesmaids get ready at the hotel, and the photo session also happens there, so the photo session does not need its own trip.

**BR-13. Cars belong to trips.** A member registers their car separately for each trip they can drive on. Seats, passengers, cargo, and requests all belong to one car on one trip.

---

## 6. Cars

**BR-14. Registering a car for the To the hotel trip.** Registering a car means "I'm coming with my car." The driver answers these questions:

| Field | Input | Notes |
|---|---|---|
| Home area | Dropdown: Maadi, Zahraa El Maadi, October, Other | Choosing **Other** opens a free-text field. |
| Available seats | Number | The number of passenger seats. |
| Departure window | Earliest and latest time to leave home | The form shows this note: *"Only choose times you're truly fine with. The bride may pick any time in this window."* |
| Travel time to the bride's house | Minutes | For drivers who stop at the bride's house on the way to the hotel. The form shows this hint: *"Check Google Maps for the estimate."* |
| Travel time to the hotel | Minutes | The form shows the same Google Maps hint. |
| Stops before the destination | A list of stops | Each stop is labeled **For myself** or **For the bride**. |
| Guaranteed trunk space | Dropdown: 0%, 25%, 50%, 75%, 100% | For information only (see BR-17). |
| Notes | Free text | Optional. |

**BR-15. Registering a car for the Hotel to venue and Return home trips.** The driver answers these questions:

| Field | Input | Notes |
|---|---|---|
| Departure window | Earliest and latest time to leave the hotel (Hotel to venue) or the venue (Return home) | The form shows the same note: *"Only choose times you're truly fine with. The bride may pick any time in this window."* |
| Areas I can drop people off in | Dropdown: Maadi, Zahraa El Maadi, October, Other (with free text) | **Return home only.** The driver can choose more than one area. |
| Available seats | Number | The number of passenger seats. |
| Guaranteed trunk space | Dropdown: 0%, 25%, 50%, 75%, 100% | For information only (see BR-17). |
| Notes | Free text | Optional. |

**BR-16. Car notes.** Car notes are **one-way** and **visible to all members**. No one can reply to them.

**BR-17. Trunk space.** Trunk space is for information only. Cargo has no size field, and the app never blocks a cargo request because of trunk space. The car owner decides whether something fits when they accept or decline the request.

**BR-18. What everyone can see.** All members can see, for every car:
- how many passengers are confirmed and who they are, and
- what cargo is confirmed.

**BR-19. Withdrawing a car.** A car owner can withdraw their car from a trip. Withdrawing cancels every passenger and cargo assignment in that car. Affected members see the change in their "Needs your attention" section (BR-34).

---

## 7. Requests (Passengers and Cargo)

**BR-20. Request directions.** A request places a passenger or cargo in a car on a specific trip. It has one of two directions:

| Direction | Example | Who starts it | Who must accept |
|---|---|---|---|
| **Ask** | "I want to ride your car." | The passenger, or the cargo's owner | The car owner |
| **Offer** | "Do you want to ride my car?" | The car owner | The passenger, or the cargo's owner |

**BR-21. When a request is confirmed.** A request is confirmed when the other party accepts it. Before that point:
- either party can decline, and
- the person who started the request can cancel it.

After confirmation, a passenger can withdraw from the car, and a cargo's owner can withdraw their item or container from it. This frees the seat and appears in the car owner's "Needs your attention" section (BR-34). A car owner can't remove a confirmed passenger or cargo.

**BR-22. One car per trip.** A passenger, item, or container can be confirmed in only **one car per trip**. When one of its requests is confirmed, its other pending requests for that same trip are cancelled automatically.

**BR-23. Full cars.** No one can send any request (Ask or Offer) for a car with no free seats. When a car's last seat is filled, its remaining pending passenger requests are cancelled automatically. Seat limits apply to passengers only.

**BR-24. Cargo requests.** Cargo requests follow the same two directions and the same rules as passenger requests. Each cargo request also includes:
- the **item or container** being carried,
- the **pickup location**, which is the bride's home, the vendor's address (when the item has vendor details), or a custom address, and
- the **ready-for-pickup time** (optional).

The **cargo's owner** is the member who created a personal item, the member who claimed a claimable item, or the member who created a container. Unclaimed items can't be sent as cargo.

**BR-25. Requests list.** Each member has one **Requests** list showing every request they sent or received, with its current state. It can be filtered by:
- **Direction:** sent or received
- **State:** Pending, Confirmed, Declined, or Cancelled
- **Kind:** passenger or cargo

The member can accept or decline received pending requests, and cancel sent pending requests, from this list.

---

## 8. Wedding-Day Status

**BR-26. Statuses.** Every member, including the Bride, always has one of these statuses:
- At home
- At the bride's house
- Transporting to the hotel
- Between the hotel and the venue
- Running a personal errand
- Running an errand for the bride
- Doing makeup
- Dressing up
- Photo session
- At the venue
- Heading home

**BR-27. Changing status.** Each member's status starts as **"At home."** The member's current status is shown at the top of every screen and can be changed with one tap.

**BR-28. Status board.** A status board shows every member's current status and how long ago they updated it, for example "Sara: Doing makeup, 12 min ago." A member's status does not show which car they are in.

---

## 9. Vendors

Vendors are not a separate entity. Vendor information is stored on shared claimable items.

**BR-29. Vendor details on items.** A shared claimable item can have an optional **Vendor details** section with these fields:

| Field | Example |
|---|---|
| Vendor name | Ahmed Hassan |
| Service | Photographer |
| Phone number | 01X XXXX XXXX |
| Address | Optional; used as a pickup location (see BR-24) |
| Expected arrival or ready-for-pickup time | 5:00 pm |
| Amount to be paid | 2,000 EGP |
| Extra details | Free text for anything else to coordinate |

Services with no physical goods, such as the photographer or makeup artist, are added as claimable items too, for example an item named "Photographer." Packed status and cargo requests are simply not used for these items.

**BR-30. Responsibility.** The member who claims an item with vendor details is the person responsible for that vendor, including meeting them. This follows the normal claim rules in BR-08: a member takes on a vendor by claiming the item.

**BR-31. Vendor permissions.** Any member can add, edit, or remove an item's vendor details, and all members can view them.

**BR-32. Vendors filter.** Applying the **"Has vendor details"** filter to the Items list (BR-09a) shows every vendor, sorted by arrival or ready-for-pickup time. Each row shows the vendor, their service, the time, the amount to be paid, and who claimed the item, or "Unclaimed."

---

## 10. Notifications

**BR-33. No notifications.** The app does not send push, SMS, email, or WhatsApp notifications.

**BR-34. "Needs your attention" section.** Each member's home screen has a **"Needs your attention"** section. It lists:
- pending ride and cargo requests waiting for the member to respond, and
- anything that affected the member and was cancelled since their last visit, such as a withdrawn car or an auto-cancelled request.
