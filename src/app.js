const API_URL = CONFIG.API_URL;


// Temporary chart data
// We will make this dynamic from DynamoDB later.
const days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const volumes = [58, 73, 66, 91, 84, 49, 88];


function render(data) {

  // =========================
  // Summary data from API
  // =========================

  const total = data.summary.total;
  const completed = data.summary.completed;
  const failed = data.summary.failed;
  const pending = data.summary.pending;

  const rate = total > 0
    ? Math.round((completed / total) * 100)
    : 0;

  const failureRate = total > 0
    ? Math.round((failed / total) * 100)
    : 0;


  // =========================
  // Summary cards
  // =========================

  document.querySelector("#total").textContent = total;

  document.querySelector("#completed").textContent =
    completed;

  document.querySelector("#failed").textContent =
    failed;

  document.querySelector("#completionRate").textContent =
    rate + "% completion rate";

  document.querySelector("#failureRate").textContent =
    failureRate + "% failure rate";

  document.querySelector("#aht").textContent =
    data.summary.avg_processing_time;


  // =========================
  // Donut chart
  // =========================

  document.querySelector("#donutPct").textContent =
    rate + "%";

  document.querySelector("#legendCompleted").textContent =
    completed;

  document.querySelector("#legendFailed").textContent =
    failed;

  document.querySelector("#legendPending").textContent =
    pending;

  document.querySelector("#donut").style.background =
    `conic-gradient(
      #172033 0 ${rate}%,
      #aeb6c3 ${rate}% 100%
    )`;


  // =========================
  // Daily volume chart
  // =========================

  const max = Math.max(...volumes, 1);

  document.querySelector("#chart").innerHTML =
    volumes
      .map(
        v =>
          `<div
             class="bar"
             title="${v} transactions"
             style="height:${(v / max) * 100}%">
           </div>`
      )
      .join("");

  document.querySelector("#labels").innerHTML =
    days
      .map(d => `<span>${d}</span>`)
      .join("");


  // =========================
  // Transaction table
  // =========================

  document.querySelector("#rows").innerHTML =
    data.transactions
      .map(t => {

        const status = t.status.toUpperCase();

        const cls =
          status === "COMPLETED"
            ? "completed"
            : status === "FAILED"
            ? "failed-b"
            : "pending-b";

        return `
          <tr>
            <td>
              <b>${t.transaction_id}</b>
            </td>

            <td>
              ${t.customer}
            </td>

            <td>
              ${t.automation_name}
            </td>

            <td>
              <span class="badge ${cls}">
                ${status}
              </span>
            </td>

            <td>
              ${t.processing_time != null
                ? t.processing_time + " min"
                : "—"}
            </td>
          </tr>
        `;
      })
      .join("");
}


// =========================
// API call
// =========================

async function refreshData() {

  const refreshButton =
    document.getElementById("refreshBtn");

  try {

    refreshButton.disabled = true;
    refreshButton.textContent = "Refreshing...";


    const response = await fetch(API_URL);


    if (!response.ok) {

      throw new Error(
        `API request failed: ${response.status}`
      );

    }


    const data = await response.json();

    console.log("API RESPONSE:", data);


    // Render API data
    render(data);


    refreshButton.textContent =
      "Refresh data";


  } catch (error) {

    console.error(
      "Failed to fetch transaction data:",
      error
    );


    refreshButton.textContent =
      "Refresh failed";


    setTimeout(() => {

      refreshButton.textContent =
        "Refresh data";

    }, 2000);


  } finally {

    refreshButton.disabled = false;

  }
}


// =========================
// Refresh button
// =========================

document
  .querySelector("#refreshBtn")
  .addEventListener(
    "click",
    refreshData
  );


// =========================
// Initial page load
// =========================

refreshData();