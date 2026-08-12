import {
  renderPdf, drawHeader, drawTitle, drawField, drawParagraph, drawTable,
  drawSignatures, drawIssuedNote, fetchImage,
  formatDate, formatMoney, BRAND, LANDSCAPE,
} from './letterhead.js';

// Builds the reviewer/authority signature blocks shared by every approved
// document. `reviewer` may be absent when a submission was approved directly.
function signatories(reviewer, approver, leaveHolder = null) {
  const blocks = [];
  if (leaveHolder) {
    blocks.push({
      name: leaveHolder.full_name,
      title: leaveHolder.designation,
      signature_url: null,           // applicant signs on the printed copy
      caption: 'Applicant',
    });
  }
  if (reviewer) {
    blocks.push({
      name: reviewer.full_name,
      title: reviewer.signature_title || reviewer.designation || 'Reporting Officer',
      signature_url: reviewer.signature_url,
      at: reviewer.acted_at,
      caption: 'Recommended by',
    });
  }
  if (approver) {
    blocks.push({
      name: approver.full_name,
      title: approver.signature_title || approver.designation || 'Authorised Signatory',
      signature_url: approver.signature_url,
      at: approver.acted_at,
      caption: 'Approved by',
    });
  }
  return blocks;
}

const STATUS_LABEL = {
  draft: 'Draft', submitted: 'Submitted', reviewed: 'Recommended',
  approved: 'Approved', rejected: 'Rejected', cancelled: 'Cancelled', paid: 'Paid',
};

// A coloured status chip so a printed document reads at a glance.
function drawStatusChip(doc, status) {
  const label = (STATUS_LABEL[status] || status).toUpperCase();
  const colours = {
    approved: ['#e6f4ea', '#1a7f37'],
    paid: ['#e6f4ea', '#1a7f37'],
    rejected: ['#fdecea', '#b3261e'],
    reviewed: ['#fff4e5', '#8a5300'],
  };
  const [bg, fg] = colours[status] || ['#eef3f0', BRAND.green];
  const right = doc.page.width - doc.page.margins.right;
  const w = Math.max(70, doc.widthOfString(label) + 18);
  const y = doc.y;
  doc.roundedRect(right - w, y, w, 16, 8).fillColor(bg).fill();
  doc.fontSize(8).fillColor(fg).font('Helvetica-Bold')
    .text(label, right - w, y + 4.5, { width: w, align: 'center' });
  doc.y = y + 22;
}

// ---------------------------------------------------------------------------
// Leave approval letter
// ---------------------------------------------------------------------------
export function buildLeaveLetter({ leave, employee, reviewer, approver, handover, fileNo }) {
  return renderPdf(async (doc) => {
    await drawHeader(doc, fileNo, leave.approved_at || new Date());
    drawTitle(doc, 'Leave Approval Letter');
    drawStatusChip(doc, leave.status);

    drawParagraph(doc, null,
      `The leave application submitted by ${employee.full_name} ` +
      `(${employee.designation || 'Staff'}, Employee Code ${employee.emp_code}) has been ` +
      `${leave.status === 'approved' ? 'examined and approved' : 'processed'} as detailed below.`);

    drawField(doc, 'Employee Name', employee.full_name, { bold: true });
    drawField(doc, 'Employee Code', employee.emp_code);
    drawField(doc, 'Designation', employee.designation);
    drawField(doc, 'Department', employee.department);
    drawField(doc, 'Type of Leave', leave.leave_type_name, { bold: true });
    drawField(doc, 'Period of Leave',
      `${formatDate(leave.from_date)}  to  ${formatDate(leave.to_date)}`, { bold: true });
    drawField(doc, 'Number of Days',
      `${leave.days} ${Number(leave.days) === 1 ? 'day' : 'days'}${leave.is_half_day ? ' (half day)' : ''}`);
    if (handover) drawField(doc, 'Duties Handed Over To', handover.full_name);
    if (leave.address_on_leave) drawField(doc, 'Address During Leave', leave.address_on_leave);
    if (leave.contact_on_leave) drawField(doc, 'Contact During Leave', leave.contact_on_leave);
    doc.moveDown(0.5);

    drawParagraph(doc, 'Reason for Leave', leave.reason);
    if (leave.review_remark) drawParagraph(doc, 'Remarks of Reporting Officer', leave.review_remark);
    if (leave.approve_remark) drawParagraph(doc, 'Remarks of Approving Authority', leave.approve_remark);

    if (leave.status === 'approved') {
      drawParagraph(doc, null,
        `The above leave is sanctioned. ${employee.full_name} is instructed to resume duty on ` +
        `${formatDate(nextWorkingDay(leave.to_date))} unless an extension is separately sanctioned.`);
    }

    await drawSignatures(doc, signatories(reviewer, approver));
    drawIssuedNote(doc, fileNo);
  });
}

// Resume-duty date: the calendar day after leave ends. Weekly offs are not
// resolved here because the office's off-days are configurable per settings and
// the letter only needs to state the expected resumption date.
function nextWorkingDay(toDate) {
  const d = new Date(toDate);
  d.setDate(d.getDate() + 1);
  return d;
}

// ---------------------------------------------------------------------------
// Periodic work report
// ---------------------------------------------------------------------------
export function buildWorkReport({ report, employee, reviewer, approver, fileNo }) {
  const periodLabel = {
    daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly', quarterly: 'Quarterly',
  }[report.period] || 'Periodic';

  return renderPdf(async (doc) => {
    await drawHeader(doc, fileNo, report.approved_at || new Date());
    drawTitle(doc, `${periodLabel} Work Report`,
      `${formatDate(report.period_start)} — ${formatDate(report.period_end)}`);
    drawStatusChip(doc, report.status);

    drawField(doc, 'Submitted By', employee.full_name, { bold: true });
    drawField(doc, 'Employee Code', employee.emp_code);
    drawField(doc, 'Designation', employee.designation);
    drawField(doc, 'Department', employee.department);
    if (report.project_name) drawField(doc, 'Project / Programme', report.project_name);
    drawField(doc, 'Reporting Period',
      `${formatDate(report.period_start)} to ${formatDate(report.period_end)}`);
    drawField(doc, 'Submitted On', formatDate(report.created_at));
    doc.moveDown(0.6);

    drawParagraph(doc, 'Subject', report.title);
    drawParagraph(doc, 'Summary of Work Done', report.summary);
    if (report.achievements) drawParagraph(doc, 'Key Achievements', report.achievements);
    if (report.challenges) drawParagraph(doc, 'Challenges Faced', report.challenges);
    if (report.next_plan) drawParagraph(doc, 'Plan for Next Period', report.next_plan);
    if (report.review_remark) drawParagraph(doc, 'Remarks of Reporting Officer', report.review_remark);
    if (report.approve_remark) drawParagraph(doc, 'Remarks of Approving Authority', report.approve_remark);

    await drawSignatures(doc, signatories(reviewer, approver));
    drawIssuedNote(doc, fileNo);
  });
}

// ---------------------------------------------------------------------------
// Project / activity report
// ---------------------------------------------------------------------------
export function buildActivityReport({ activity, employee, project, photos, reviewer, approver, fileNo }) {
  return renderPdf(async (doc) => {
    await drawHeader(doc, fileNo, activity.approved_at || new Date());
    drawTitle(doc, 'Activity Report', project ? `${project.name} (${project.code})` : null);
    drawStatusChip(doc, activity.status);

    drawParagraph(doc, 'Activity', activity.title);

    drawField(doc, 'Date of Activity',
      activity.end_date && activity.end_date !== activity.activity_date
        ? `${formatDate(activity.activity_date)} to ${formatDate(activity.end_date)}`
        : formatDate(activity.activity_date), { bold: true });
    drawField(doc, 'Venue', activity.venue);
    drawField(doc, 'District', activity.district);
    if (project) {
      drawField(doc, 'Project', `${project.name} (${project.code})`);
      if (project.funder) drawField(doc, 'Supported By', project.funder);
    }
    drawField(doc, 'Reported By', `${employee.full_name} (${employee.designation || 'Staff'})`);
    doc.moveDown(0.6);

    const male = activity.participants_male || 0;
    const female = activity.participants_female || 0;
    const other = activity.participants_other || 0;
    doc.fontSize(10.5).fillColor(BRAND.green).font('Helvetica-Bold')
      .text('Participation', doc.page.margins.left, doc.y);
    doc.moveDown(0.3);
    drawTable(doc, [
      { label: 'Male', key: 'm', width: 110, align: 'center' },
      { label: 'Female', key: 'f', width: 110, align: 'center' },
      { label: 'Other', key: 'o', width: 110, align: 'center' },
      { label: 'Total Participants', key: 't', width: 165, align: 'center' },
    ], [{ m: male, f: female, o: other, t: male + female + other }]);

    if (activity.beneficiaries) drawField(doc, 'Indirect Beneficiaries', activity.beneficiaries);
    if (activity.expenditure_paise) {
      drawField(doc, 'Expenditure Incurred', formatMoney(activity.expenditure_paise), { bold: true });
    }
    doc.moveDown(0.4);

    drawParagraph(doc, 'Description of Activity', activity.description);
    if (activity.outcome) drawParagraph(doc, 'Outcome & Impact', activity.outcome);
    if (activity.challenges) drawParagraph(doc, 'Challenges', activity.challenges);
    if (activity.review_remark) drawParagraph(doc, 'Remarks of Reporting Officer', activity.review_remark);
    if (activity.approve_remark) drawParagraph(doc, 'Remarks of Approving Authority', activity.approve_remark);

    // Photo evidence, two per row on a fresh page so the narrative stays clean.
    const images = (photos || []).length
      ? await Promise.all(photos.slice(0, 8).map((p) => fetchImage(p.url)))
      : [];
    const usable = images.filter(Boolean);
    if (usable.length) {
      doc.addPage();
      await drawHeader(doc, fileNo, activity.approved_at || new Date());
      drawTitle(doc, 'Photographs', activity.title);

      const left = doc.page.margins.left;
      const width = doc.page.width - left - doc.page.margins.right;
      const cellW = (width - 12) / 2;
      const cellH = 150;
      let x = left;
      let y = doc.y;

      usable.forEach((img, i) => {
        if (y + cellH + 26 > doc.page.height - doc.page.margins.bottom) {
          doc.addPage();
          y = doc.page.margins.top;
          x = left;
        }
        try {
          doc.image(img, x, y, { fit: [cellW, cellH], align: 'center', valign: 'center' });
        } catch {
          // Skip an unreadable image rather than failing the whole report.
        }
        const caption = photos[i]?.caption;
        if (caption) {
          doc.fontSize(7.5).fillColor(BRAND.muted).font('Helvetica')
            .text(caption, x, y + cellH + 3, { width: cellW, align: 'center' });
        }
        if (i % 2 === 0) {
          x += cellW + 12;
        } else {
          x = left;
          y += cellH + 26;
        }
      });
      doc.y = y + cellH + 26;
    }

    await drawSignatures(doc, signatories(reviewer, approver));
    drawIssuedNote(doc, fileNo);
  });
}

// ---------------------------------------------------------------------------
// TA / DA sanction & settlement
// ---------------------------------------------------------------------------
const MODE_LABEL = {
  bus: 'Bus', train: 'Train', air: 'Air', taxi: 'Taxi',
  two_wheeler: 'Two Wheeler', own_car: 'Own Car', shared: 'Shared Vehicle', other: 'Other',
};

export function buildTaDaClaim({ claim, employee, legs, project, reviewer, approver, fileNo }) {
  return renderPdf(async (doc) => {
    await drawHeader(doc, fileNo, claim.approved_at || new Date());
    drawTitle(doc, 'Travelling & Daily Allowance Bill',
      claim.claim_no ? `Claim No. ${claim.claim_no}` : null);
    drawStatusChip(doc, claim.status);

    drawField(doc, 'Name of Claimant', employee.full_name, { bold: true });
    drawField(doc, 'Employee Code', employee.emp_code);
    drawField(doc, 'Designation', employee.designation);
    drawField(doc, 'Grade', employee.grade);
    if (project) drawField(doc, 'Project / Programme', `${project.name} (${project.code})`);
    drawField(doc, 'Period of Journey',
      `${formatDate(claim.from_date)}  to  ${formatDate(claim.to_date)}`, { bold: true });
    doc.moveDown(0.4);
    drawParagraph(doc, 'Purpose of Journey', claim.purpose);

    doc.fontSize(10.5).fillColor(BRAND.green).font('Helvetica-Bold')
      .text('Details of Journey', doc.page.margins.left, doc.y);
    doc.moveDown(0.3);

    const rows = (legs || []).map((l, i) => ({
      sn: i + 1,
      date: formatDate(l.travel_date),
      route: `${l.from_place} to ${l.to_place}`,
      mode: MODE_LABEL[l.mode] || l.mode,
      km: l.distance_km ? Number(l.distance_km).toFixed(1) : '—',
      fare: formatMoney(l.fare_paise).replace('Rs. ', ''),
      da: l.da_paise ? formatMoney(l.da_paise).replace('Rs. ', '') : '—',
      lodging: l.lodging_paise ? formatMoney(l.lodging_paise).replace('Rs. ', '') : '—',
      other: l.other_paise ? formatMoney(l.other_paise).replace('Rs. ', '') : '—',
    }));

    drawTable(doc, [
      { label: '#', key: 'sn', width: 22, align: 'center' },
      { label: 'Date', key: 'date', width: 62 },
      { label: 'From / To', key: 'route', width: 122 },
      { label: 'Mode', key: 'mode', width: 58 },
      { label: 'Km', key: 'km', width: 32, align: 'right' },
      { label: 'Fare', key: 'fare', width: 52, align: 'right' },
      { label: 'DA', key: 'da', width: 48, align: 'right' },
      { label: 'Lodging', key: 'lodging', width: 50, align: 'right' },
      { label: 'Other', key: 'other', width: 49, align: 'right' },
    ], rows, {
      onNewPage: (d) => { d.y = d.page.margins.top; },
    });

    // Right-aligned totals ladder.
    const left = doc.page.margins.left;
    const right = doc.page.width - doc.page.margins.right;
    const labelW = 150;
    const total = (label, value, bold = false) => {
      const y = doc.y;
      doc.fontSize(9.5).fillColor(BRAND.body).font(bold ? 'Helvetica-Bold' : 'Helvetica')
        .text(label, right - labelW - 90, y, { width: labelW, align: 'right' });
      doc.fontSize(9.5).fillColor(BRAND.ink).font(bold ? 'Helvetica-Bold' : 'Helvetica')
        .text(value, right - 90, y, { width: 90, align: 'right' });
      doc.y = y + 14;
    };

    total('Total Fare', formatMoney(claim.fare_paise));
    total('Total Daily Allowance', formatMoney(claim.da_paise));
    total('Total Lodging', formatMoney(claim.lodging_paise));
    total('Other Expenses', formatMoney(claim.other_paise));
    doc.moveTo(right - labelW - 90, doc.y).lineTo(right, doc.y)
      .strokeColor('#cccccc').lineWidth(0.6).stroke();
    doc.y += 4;
    total('Gross Amount Claimed', formatMoney(claim.total_paise), true);
    if (claim.advance_paise) total('Less: Advance Drawn', `(-) ${formatMoney(claim.advance_paise)}`);
    if (claim.sanctioned_paise != null && claim.sanctioned_paise !== claim.total_paise) {
      total('Amount Sanctioned', formatMoney(claim.sanctioned_paise), true);
    }
    doc.moveTo(right - labelW - 90, doc.y).lineTo(right, doc.y)
      .strokeColor(BRAND.green).lineWidth(1).stroke();
    doc.y += 4;
    total('Net Amount Payable', formatMoney(claim.net_payable_paise), true);
    doc.moveDown(0.8);

    doc.fontSize(8.5).fillColor(BRAND.muted).font('Helvetica-Oblique')
      .text(
        'Certified that the journey was actually performed in the interest of the Foundation and that ' +
        'the amount claimed is correct and has not been claimed earlier.',
        left, doc.y, { width: right - left, align: 'justify' }
      );
    doc.moveDown(0.4);

    if (claim.review_remark) drawParagraph(doc, 'Remarks of Reporting Officer', claim.review_remark);
    if (claim.approve_remark) drawParagraph(doc, 'Remarks of Approving Authority', claim.approve_remark);
    if (claim.status === 'paid' && claim.payment_ref) {
      drawField(doc, 'Payment Reference', claim.payment_ref);
      drawField(doc, 'Paid On', formatDate(claim.paid_at));
    }

    // The claimant certifies the bill, so they sign alongside the approvers.
    await drawSignatures(doc, signatories(reviewer, approver, employee));
    drawIssuedNote(doc, fileNo);
  });
}

// ---------------------------------------------------------------------------
// Monthly attendance muster roll
// ---------------------------------------------------------------------------

// Single-letter day codes used in the grid, with a legend beneath.
const DAY_CODE = {
  present: 'P', field: 'F', wfh: 'W', leave: 'L',
  holiday: 'H', weekly_off: 'O', absent: 'A', future: '·',
};

export function buildAttendanceMuster({ month, year, rows, days, authority, fileNo, employee }) {
  const monthName = new Date(year, month - 1, 1)
    .toLocaleDateString('en-IN', { month: 'long', year: 'numeric' });

  // Landscape gives room for up to 31 day-columns.
  return renderPdf(async (doc) => {
    await drawHeader(doc, fileNo, new Date());
    drawTitle(doc, 'Attendance Register', `${monthName}${employee ? ` — ${employee.full_name}` : ''}`);

    const left = doc.page.margins.left;
    const right = doc.page.width - doc.page.margins.right;
    const nameW = 150;
    const summaryW = 108;
    const dayW = (right - left - nameW - summaryW) / days;

    // Header row: day numbers.
    let y = doc.y;
    doc.rect(left, y, right - left, 16).fillColor('#eef3f0').fill();
    doc.fontSize(7.5).fillColor(BRAND.green).font('Helvetica-Bold')
      .text('Name of Employee', left + 4, y + 5, { width: nameW - 8 });
    for (let d = 1; d <= days; d++) {
      doc.text(String(d), left + nameW + (d - 1) * dayW, y + 5, { width: dayW, align: 'center' });
    }
    doc.text('P / L / A', right - summaryW + 4, y + 5, { width: summaryW - 8, align: 'center' });
    y += 16;

    doc.font('Helvetica').fontSize(7);
    for (const row of rows) {
      if (y + 15 > doc.page.height - doc.page.margins.bottom) {
        doc.addPage();
        await drawHeader(doc, fileNo, new Date());
        y = doc.y;
      }

      doc.fillColor(BRAND.ink).fontSize(7.5).font('Helvetica')
        .text(row.full_name, left + 4, y + 4, { width: nameW - 8, ellipsis: true, height: 10 });

      for (let d = 1; d <= days; d++) {
        const state = row.marks[d] || 'absent';
        const code = DAY_CODE[state] || '';
        // Tint the cell so patterns (leave runs, field weeks) are visible.
        const tint = {
          leave: '#fff4e5', absent: '#fdecea', holiday: '#f0f0f0',
          weekly_off: '#f7f7f7', field: '#e8f1fb', wfh: '#f3ecfb',
        }[state];
        const cx = left + nameW + (d - 1) * dayW;
        if (tint) doc.rect(cx, y, dayW, 15).fillColor(tint).fill();
        doc.fillColor(state === 'absent' ? '#b3261e' : BRAND.body).fontSize(7)
          .text(code, cx, y + 4.5, { width: dayW, align: 'center' });
      }

      doc.fillColor(BRAND.ink).fontSize(7.5).font('Helvetica-Bold')
        .text(`${row.summary.present} / ${row.summary.leave} / ${row.summary.absent}`,
          right - summaryW + 4, y + 4, { width: summaryW - 8, align: 'center' });

      y += 15;
      doc.moveTo(left, y).lineTo(right, y).strokeColor('#e2e8e5').lineWidth(0.4).stroke();
    }

    doc.y = y + 10;
    doc.fontSize(7.5).fillColor(BRAND.muted).font('Helvetica')
      .text(
        'Legend:  P = Present (office)   F = Field duty   W = Work from home   ' +
        'L = Leave   H = Holiday   O = Weekly off   A = Absent   · = Not yet due',
        left, doc.y, { width: right - left }
      );
    doc.moveDown(0.5);
    doc.fontSize(7.5).fillColor(BRAND.faint).font('Helvetica-Oblique')
      .text(
        'Attendance captured through geo-tagged photo check-in on the NESF Core application.',
        left, doc.y, { width: right - left }
      );

    await drawSignatures(doc, [
      authority && {
        name: authority.full_name,
        title: authority.signature_title || authority.designation || 'Authorised Signatory',
        signature_url: authority.signature_url,
        caption: 'Certified by',
      },
    ].filter(Boolean));
    drawIssuedNote(doc, fileNo);
  }, LANDSCAPE);
}

// ---------------------------------------------------------------------------
// Project consolidated report
// ---------------------------------------------------------------------------
export function buildProjectReport({ project, activities, totals, lead, authority, fileNo }) {
  return renderPdf(async (doc) => {
    await drawHeader(doc, fileNo, new Date());
    drawTitle(doc, 'Project Report', `${project.name} (${project.code})`);

    drawField(doc, 'Project Name', project.name, { bold: true });
    drawField(doc, 'Project Code', project.code);
    drawField(doc, 'Sport / Discipline', project.sport);
    drawField(doc, 'Location', [project.district, project.state].filter(Boolean).join(', '));
    drawField(doc, 'Duration',
      `${formatDate(project.start_date)} to ${formatDate(project.end_date)}`);
    drawField(doc, 'Supported By', project.funder);
    drawField(doc, 'Sanctioned Budget', formatMoney(project.budget_paise), { bold: true });
    if (lead) drawField(doc, 'Project Lead', `${lead.full_name} (${lead.designation || 'Staff'})`);
    drawField(doc, 'Status', STATUS_LABEL[project.status] || project.status);
    doc.moveDown(0.5);

    if (project.description) drawParagraph(doc, 'About the Project', project.description);

    doc.fontSize(10.5).fillColor(BRAND.green).font('Helvetica-Bold')
      .text('Summary of Impact', doc.page.margins.left, doc.y);
    doc.moveDown(0.3);
    drawTable(doc, [
      { label: 'Activities Conducted', key: 'a', width: 124, align: 'center' },
      { label: 'Total Participants', key: 'p', width: 124, align: 'center' },
      { label: 'Beneficiaries', key: 'b', width: 124, align: 'center' },
      { label: 'Expenditure', key: 'e', width: 123, align: 'center' },
    ], [{
      a: totals.activity_count,
      p: totals.participants,
      b: totals.beneficiaries,
      e: formatMoney(totals.expenditure_paise),
    }]);

    doc.fontSize(10.5).fillColor(BRAND.green).font('Helvetica-Bold')
      .text('Activities Undertaken', doc.page.margins.left, doc.y);
    doc.moveDown(0.3);
    drawTable(doc, [
      { label: '#', key: 'sn', width: 24, align: 'center' },
      { label: 'Date', key: 'date', width: 68 },
      { label: 'Activity', key: 'title', width: 170 },
      { label: 'Venue', key: 'venue', width: 100 },
      { label: 'Partic.', key: 'part', width: 42, align: 'right' },
      { label: 'Expenditure', key: 'exp', width: 91, align: 'right' },
    ], activities.map((a, i) => ({
      sn: i + 1,
      date: formatDate(a.activity_date),
      title: a.title,
      venue: a.venue || '—',
      part: (a.participants_male || 0) + (a.participants_female || 0) + (a.participants_other || 0),
      exp: formatMoney(a.expenditure_paise).replace('Rs. ', ''),
    })), { onNewPage: (d) => { d.y = d.page.margins.top; } });

    const balance = (project.budget_paise || 0) - (totals.expenditure_paise || 0);
    if (project.budget_paise) {
      drawField(doc, 'Budget Utilised',
        `${formatMoney(totals.expenditure_paise)} of ${formatMoney(project.budget_paise)}` +
        ` (${((totals.expenditure_paise / project.budget_paise) * 100).toFixed(1)}%)`, { bold: true });
      drawField(doc, 'Balance Available', formatMoney(balance));
    }

    await drawSignatures(doc, [
      lead && {
        name: lead.full_name,
        title: lead.signature_title || lead.designation || 'Project Lead',
        signature_url: lead.signature_url,
        caption: 'Prepared by',
      },
      authority && {
        name: authority.full_name,
        title: authority.signature_title || authority.designation || 'Authorised Signatory',
        signature_url: authority.signature_url,
        caption: 'Approved by',
      },
    ].filter(Boolean));
    drawIssuedNote(doc, fileNo);
  });
}
