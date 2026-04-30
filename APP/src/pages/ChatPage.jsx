import { useState, useRef, useEffect } from 'react';
import { Send, Bot, User, Loader2, AlertTriangle, CheckCircle, Shield, MessageSquare, Pill, Phone, ArrowUpRight, ClipboardList, AlertCircle, Cpu } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { sendChatMessage, onChatMessage, getWebSocket } from '../api';

// Simple markdown-style text renderer for AgentCore responses
function MarkdownText({ text, isStreaming }) {
  if (!text) return null;

  const lines = text.split('\n');
  const elements = [];
  let key = 0;
  let tableRows = [];
  let tableHeaders = [];
  let inTable = false;

  const flushTable = () => {
    if (tableHeaders.length > 0 || tableRows.length > 0) {
      elements.push(
        <div key={key++} className="overflow-x-auto my-2">
          <table className="w-full text-xs border border-gray-200 rounded-lg overflow-hidden">
            {tableHeaders.length > 0 && (
              <thead className="bg-gray-50">
                <tr>
                  {tableHeaders.map((h, i) => (
                    <th key={i} className="px-3 py-2 text-left font-semibold text-gray-700 border-b border-gray-200"
                        dangerouslySetInnerHTML={{ __html: fmtBold(h.trim()) }} />
                  ))}
                </tr>
              </thead>
            )}
            <tbody>
              {tableRows.map((row, ri) => (
                <tr key={ri} className={ri % 2 === 0 ? 'bg-white' : 'bg-gray-50'}>
                  {row.map((cell, ci) => (
                    <td key={ci} className="px-3 py-1.5 text-gray-700 border-b border-gray-100"
                        dangerouslySetInnerHTML={{ __html: fmtBold(cell.trim()) }} />
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
      tableHeaders = [];
      tableRows = [];
      inTable = false;
    }
  };

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const trimmed = line.trim();

    // Empty line
    if (!trimmed) {
      flushTable();
      elements.push(<div key={key++} className="h-1.5" />);
      continue;
    }

    // Table row: | col | col | col |
    if (trimmed.startsWith('|') && trimmed.endsWith('|')) {
      const cells = trimmed.split('|').filter(c => c.trim() !== '');
      // Separator row: |---|---|
      if (cells.every(c => /^[\s-:]+$/.test(c))) {
        inTable = true;
        continue;
      }
      if (!inTable && tableHeaders.length === 0) {
        tableHeaders = cells;
      } else {
        tableRows.push(cells);
        inTable = true;
      }
      continue;
    }

    // If we were in a table, flush it
    flushTable();

    // Horizontal rule: --- or ───
    if (/^[-─]{3,}$/.test(trimmed)) {
      elements.push(<hr key={key++} className="my-3 border-gray-200" />);
      continue;
    }

    // Tool indicator: 🔧 tool_name
    if (trimmed.startsWith('🔧')) {
      elements.push(
        <div key={key++} className="flex items-center gap-2 my-1 px-3 py-1.5 bg-blue-50 border border-blue-100 rounded-lg text-xs text-blue-700">
          <span>🔧</span>
          <span className="font-mono font-medium">{trimmed.replace('🔧', '').trim()}</span>
        </div>
      );
      continue;
    }

    // Emoji section header: 🚨 Title or 📋 Title or 🔍 Title
    if (/^[🚨📋🔍⚠️✅❌💊🏥📊🎯]\s/.test(trimmed)) {
      elements.push(
        <p key={key++} className="font-bold text-gray-900 mt-4 mb-1.5 text-sm flex items-center gap-2"
           dangerouslySetInnerHTML={{ __html: fmtBold(trimmed) }} />
      );
      continue;
    }

    // Bold header: **Section Name** or **Section Name:**
    if (/^\*\*[^*]+\*\*:?$/.test(trimmed)) {
      const headerText = trimmed.replace(/\*\*/g, '').replace(/:$/, '');
      elements.push(
        <p key={key++} className="font-bold text-gray-900 mt-4 mb-1.5 text-sm">{headerText}</p>
      );
      continue;
    }

    // Numbered list: 1. text or 2. text
    if (/^\d+\.\s/.test(trimmed)) {
      const num = trimmed.match(/^(\d+)\./)[1];
      const content = trimmed.replace(/^\d+\.\s/, '');
      elements.push(
        <div key={key++} className="flex gap-2.5 ml-1 text-sm text-gray-700 leading-relaxed my-0.5">
          <span className="w-5 h-5 rounded-full bg-blue-100 text-blue-700 flex items-center justify-center text-xs font-bold shrink-0 mt-0.5">{num}</span>
          <span dangerouslySetInnerHTML={{ __html: fmtBold(content) }} />
        </div>
      );
      continue;
    }

    // Bullet: - text or • text
    if (/^\s*[-•]\s/.test(line)) {
      const bulletText = line.replace(/^\s*[-•]\s/, '');
      elements.push(
        <div key={key++} className="flex gap-2 ml-2 text-sm text-gray-700 leading-relaxed my-0.5">
          <span className="text-blue-400 shrink-0 mt-1">•</span>
          <span dangerouslySetInnerHTML={{ __html: fmtBold(bulletText) }} />
        </div>
      );
      continue;
    }

    // Regular text
    elements.push(
      <p key={key++} className="text-sm text-gray-700 leading-relaxed"
         dangerouslySetInnerHTML={{ __html: fmtBold(trimmed) }} />
    );
  }

  flushTable();

  if (isStreaming) {
    elements.push(
      <span key="cursor" className="inline-block w-2 h-4 bg-blue-500 animate-pulse ml-0.5 align-middle rounded-sm" />
    );
  }

  return <div className="space-y-0.5">{elements}</div>;
}

function fmtBold(text) {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/\*\*([^*]+)\*\*/g, '<strong class="font-semibold text-gray-900">$1</strong>')
    .replace(/⚠️/g, '<span class="text-amber-500">⚠️</span>')
    .replace(/✅/g, '<span class="text-green-500">✅</span>')
    .replace(/❌/g, '<span class="text-red-500">❌</span>');
}

// Alias for backward compat
const formatInlineBold = fmtBold;

// Try to parse accumulated JSON text incrementally — extract completed fields
function tryParseIncrementalJSON(text, setSections) {
  let clean = text.trim();
  if (!clean) return;

  // Strip markdown fences
  if (clean.startsWith('```')) {
    const lines = clean.split('\n');
    const jlines = [];
    let inside = false;
    for (const line of lines) {
      if (line.trim().startsWith('```') && !inside) { inside = true; continue; }
      else if (line.trim().startsWith('```') && inside) break;
      else if (inside) jlines.push(line);
    }
    clean = jlines.join('\n');
  }

  // Try to make partial JSON parseable by adding closing characters
  const suffixes = ['', '"}', '"]', '"]}', '"}]}', '"]}}', '"]}]}'];
  let parsed = null;

  for (const suffix of suffixes) {
    try {
      parsed = JSON.parse(clean + suffix);
      break;
    } catch (e) { continue; }
  }

  if (!parsed) return;

  const newSections = {};
  if (parsed.analysis) newSections.analysis = parsed.analysis;
  if (parsed.riskAssessment) newSections.risk = parsed.riskAssessment;
  if (parsed.claimsInsight) newSections.claims = parsed.claimsInsight;
  if (parsed.careHistoryInsight) newSections.care = parsed.careHistoryInsight;
  if (parsed.medicationInsight) newSections.medication = parsed.medicationInsight;
  if (parsed.careGaps && Array.isArray(parsed.careGaps) && parsed.careGaps.length > 0) {
    newSections.gaps = parsed.careGaps;
  }
  if (parsed.recommendedInterventions && Array.isArray(parsed.recommendedInterventions) && parsed.recommendedInterventions.length > 0) {
    newSections.actions = parsed.recommendedInterventions;
  }
  if (parsed.talkingPoints && Array.isArray(parsed.talkingPoints) && parsed.talkingPoints.length > 0) {
    newSections.talkingPoints = parsed.talkingPoints;
  }

  if (Object.keys(newSections).length > 0) {
    setSections(prev => ({ ...prev, ...newSections }));
  }
}

// Try to parse as JSON first (raw Bedrock response), fall back to text parsing
function parseResponse(text) {
  if (!text) return null;

  // Try JSON parse first (Bedrock returns structured JSON)
  try {
    let jsonText = text.trim();
    // Strip markdown code fences if present
    if (jsonText.startsWith('```')) {
      const lines = jsonText.split('\n');
      const jsonLines = [];
      let inside = false;
      for (const line of lines) {
        if (line.trim().startsWith('```') && !inside) { inside = true; continue; }
        else if (line.trim().startsWith('```') && inside) break;
        else if (inside) jsonLines.push(line);
      }
      jsonText = jsonLines.join('\n');
    }
    const json = JSON.parse(jsonText);
    if (json.analysis) {
      return {
        analysis: json.analysis || '',
        risk: json.riskAssessment || '',
        claims: json.claimsInsight || '',
        care: json.careHistoryInsight || '',
        medication: json.medicationInsight || '',
        gaps: (json.careGaps || []).map(g => ({
          type: g.type || '',
          priority: g.priority || 'MEDIUM',
          due: g.dueWithin || ''
        })),
        actions: (json.recommendedInterventions || []).map(a => ({
          type: a.type || '',
          message: a.message || '',
          target: a.target || '',
          linkedGap: a.linkedGap || ''
        })),
        talkingPoints: json.talkingPoints || [],
        confidence: json.confidence || 0
      };
    }
  } catch (e) {
    // Not JSON, fall through to text parsing
  }

  // Fall back to text-based parsing
  const sections = { analysis: '', risk: '', claims: '', care: '', medication: '', gaps: [], actions: [], talkingPoints: [] };
  const lines = text.split('\n');
  let current = 'analysis';

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (trimmed.startsWith('Risk Assessment:')) { sections.risk = trimmed.replace('Risk Assessment:', '').trim(); current = 'risk'; }
    else if (trimmed.startsWith('Claims Pattern:')) { sections.claims = trimmed.replace('Claims Pattern:', '').trim(); current = 'claims'; }
    else if (trimmed.startsWith('Care Engagement:')) { sections.care = trimmed.replace('Care Engagement:', '').trim(); current = 'care'; }
    else if (trimmed.startsWith('Medication Status:')) { sections.medication = trimmed.replace('Medication Status:', '').trim(); current = 'medication'; }
    else if (trimmed === 'Care Gaps Identified:') { current = 'gaps'; }
    else if (trimmed === 'Actions Triggered:') { current = 'actions'; }
    else if (trimmed === 'Talking Points for Your Call:') { current = 'talkingPoints'; }
    else if (current === 'gaps' && (trimmed.startsWith('!!') || trimmed.startsWith('-'))) {
      const match = trimmed.match(/^[!-]+\s*(.+?)\s*\(Priority:\s*(\w+),\s*Due:\s*(.+?)\)$/);
      if (match) sections.gaps.push({ type: match[1], priority: match[2], due: match[3] });
      else sections.gaps.push({ type: trimmed.replace(/^[!-]+\s*/, ''), priority: 'MEDIUM', due: '' });
    }
    else if (current === 'actions' && trimmed.startsWith('[')) {
      const match = trimmed.match(/^\[(\w+)\]\s*(.+)$/);
      if (match) sections.actions.push({ type: match[1], message: match[2] });
    }
    else if (current === 'talkingPoints' && /^\d+\./.test(trimmed)) {
      sections.talkingPoints.push(trimmed.replace(/^\d+\.\s*/, ''));
    }
    else if (current === 'analysis' && !sections.analysis) { sections.analysis = trimmed; }
    else if (current === 'analysis') { sections.analysis += ' ' + trimmed; }
  }
  return sections;
}

// Structured agent response component
function AgentResponse({ text, meta, isStreaming, streamingSections }) {
  // If we have streaming sections, render from those
  const sectionsFromStream = streamingSections || null;

  // For completed messages, parse from text
  const sections = sectionsFromStream ? {
    analysis: sectionsFromStream.analysis || '',
    risk: sectionsFromStream.risk || '',
    claims: sectionsFromStream.claims || '',
    care: sectionsFromStream.care || '',
    medication: sectionsFromStream.medication || '',
    gaps: (sectionsFromStream.gaps || []).map(g => ({ type: g.type || '', priority: g.priority || 'MEDIUM', due: g.dueWithin || '' })),
    actions: (sectionsFromStream.actions || []).map(a => ({ type: a.type || '', message: a.message || '', target: a.target || '', linkedGap: a.linkedGap || '' })),
    talkingPoints: sectionsFromStream.talkingPoints || [],
  } : (!isStreaming ? parseResponse(text) : null);

  // While streaming, show raw text with cursor
  if (isStreaming) {
    return (
      <div className="text-sm leading-relaxed text-gray-700 whitespace-pre-wrap">
        {text}<span className="inline-block w-2 h-4 bg-blue-500 animate-pulse ml-0.5 align-middle rounded-sm" />
      </div>
    );
  }

  // Once done, show structured layout
  if (!sections || !sections.analysis) {
    return <MarkdownText text={text} isStreaming={false} />;
  }

  const priorityColors = {
    CRITICAL: 'border-l-red-500 bg-red-50',
    HIGH: 'border-l-orange-400 bg-orange-50',
    MEDIUM: 'border-l-yellow-400 bg-yellow-50',
    LOW: 'border-l-green-400 bg-green-50'
  };
  const priorityBadge = {
    CRITICAL: 'bg-red-200 text-red-800',
    HIGH: 'bg-orange-200 text-orange-800',
    MEDIUM: 'bg-yellow-200 text-yellow-800',
    LOW: 'bg-green-200 text-green-800'
  };
  const actionIcons = { SMS: MessageSquare, TASK: ClipboardList, ALERT: AlertCircle, REFERRAL: ArrowUpRight };
  const actionColors = {
    SMS: 'text-blue-600 bg-blue-100 border-blue-200',
    TASK: 'text-purple-600 bg-purple-100 border-purple-200',
    ALERT: 'text-red-600 bg-red-100 border-red-200',
    REFERRAL: 'text-green-600 bg-green-100 border-green-200'
  };

  return (
    <div className="space-y-4">
      {/* Clinical Summary */}
      <div className="bg-gray-50 rounded-xl p-4">
        <p className="text-sm leading-relaxed text-gray-800">{sections.analysis}</p>
      </div>

      {/* Risk Assessment */}
      {sections.risk && (
        <div className={`flex items-center gap-3 px-4 py-3 rounded-xl text-sm font-medium ${
          sections.risk.startsWith('HIGH') ? 'bg-red-50 text-red-800 border border-red-200' :
          sections.risk.startsWith('MEDIUM') ? 'bg-yellow-50 text-yellow-800 border border-yellow-200' :
          'bg-green-50 text-green-800 border border-green-200'
        }`}>
          <Shield className="w-5 h-5 shrink-0" />
          <div>
            <p className="font-semibold text-xs uppercase tracking-wide opacity-70 mb-0.5">Risk Assessment</p>
            <p>{sections.risk}</p>
          </div>
        </div>
      )}

      {/* Clinical Insights — 3-column grid */}
      {(sections.claims || sections.care || sections.medication) && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-2">
          {sections.claims && (
            <div className="bg-blue-50 border border-blue-100 rounded-xl p-3">
              <p className="text-xs font-semibold text-blue-500 uppercase tracking-wide mb-1">Claims Pattern</p>
              <p className="text-xs text-blue-900 leading-relaxed">{sections.claims}</p>
            </div>
          )}
          {sections.care && (
            <div className="bg-emerald-50 border border-emerald-100 rounded-xl p-3">
              <p className="text-xs font-semibold text-emerald-500 uppercase tracking-wide mb-1">Care Engagement</p>
              <p className="text-xs text-emerald-900 leading-relaxed">{sections.care}</p>
            </div>
          )}
          {sections.medication && (
            <div className="bg-orange-50 border border-orange-100 rounded-xl p-3">
              <p className="text-xs font-semibold text-orange-500 uppercase tracking-wide mb-1">Medication Status</p>
              <p className="text-xs text-orange-900 leading-relaxed">{sections.medication}</p>
            </div>
          )}
        </div>
      )}

      {/* Care Gaps */}
      {sections.gaps.length > 0 && (
        <div>
          <div className="flex items-center gap-2 mb-2">
            <AlertTriangle className="w-4 h-4 text-red-500" />
            <p className="text-xs font-semibold text-gray-600 uppercase tracking-wide">Care Gaps ({sections.gaps.length})</p>
          </div>
          <div className="space-y-1.5">
            {sections.gaps.map((g, i) => (
              <div key={i} className={`flex items-center justify-between border-l-4 pl-3 pr-3 py-2 rounded-r-xl text-sm ${priorityColors[g.priority] || priorityColors.MEDIUM}`}>
                <span className="text-gray-800 font-medium">{g.type}</span>
                <div className="flex items-center gap-2 text-xs shrink-0">
                  {g.due && <span className="text-gray-500">Due: {g.due}</span>}
                  <span className={`px-2 py-0.5 rounded-full font-bold text-xs ${priorityBadge[g.priority] || priorityBadge.MEDIUM}`}>{g.priority}</span>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Actions Triggered */}
      {sections.actions.length > 0 && (
        <div>
          <div className="flex items-center gap-2 mb-2">
            <CheckCircle className="w-4 h-4 text-green-500" />
            <p className="text-xs font-semibold text-gray-600 uppercase tracking-wide">Actions Triggered ({sections.actions.length})</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-2 gap-2">
            {sections.actions.map((a, i) => {
              const Icon = actionIcons[a.type] || CheckCircle;
              const color = actionColors[a.type] || 'text-gray-600 bg-gray-100 border-gray-200';
              return (
                <div key={i} className={`flex items-start gap-3 rounded-xl border p-3 ${color}`}>
                  <div className="w-8 h-8 rounded-lg bg-white/60 flex items-center justify-center shrink-0">
                    <Icon className="w-4 h-4" />
                  </div>
                  <div className="min-w-0">
                    <span className="text-xs font-bold uppercase tracking-wide opacity-70">{a.type}</span>
                    {a.target && <span className="text-xs opacity-50 ml-1">→ {a.target}</span>}
                    <p className="text-sm mt-0.5 leading-snug">{a.message}</p>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Talking Points */}
      {sections.talkingPoints.length > 0 && (
        <div className="bg-blue-50 border border-blue-100 rounded-xl p-4">
          <p className="text-xs font-semibold text-blue-600 uppercase tracking-wide mb-3 flex items-center gap-1.5">
            <Phone className="w-3.5 h-3.5" /> Talking Points for Your Call
          </p>
          <ol className="space-y-2 text-sm text-blue-900">
            {sections.talkingPoints.map((p, i) => (
              <li key={i} className="flex gap-3">
                <span className="w-6 h-6 rounded-full bg-blue-200 text-blue-700 flex items-center justify-center text-xs font-bold shrink-0">{i + 1}</span>
                <span className="leading-relaxed pt-0.5">{p}</span>
              </li>
            ))}
          </ol>
        </div>
      )}
    </div>
  );
}

// Animated progress steps while waiting for AI response
function ThinkingIndicator({ stage }) {
  const steps = [
    { label: 'Connecting to agent...', key: 'fetching' },
    { label: 'Retrieving data...', key: 'analyzing' },
    { label: 'Formatting response...', key: 'streaming' },
  ];

  const currentIndex = stage === 'streaming' ? 2 : stage === 'analyzing' ? 1 : 0;

  return (
    <div className="flex gap-3">
      <div className="w-8 h-8 rounded-full bg-blue-100 flex items-center justify-center mt-1">
        <Loader2 className="w-4 h-4 text-blue-600 animate-spin" />
      </div>
      <div className="bg-white border border-gray-200 rounded-2xl px-5 py-4 shadow-sm max-w-md">
        <div className="space-y-2">
          {steps.map((s, i) => (
            <div key={i} className={`flex items-center gap-2 text-sm transition-all duration-300 ${
              i < currentIndex ? 'text-green-600' : i === currentIndex ? 'text-blue-600' : 'text-gray-300'
            }`}>
              {i < currentIndex ? (
                <CheckCircle className="w-4 h-4 text-green-500 shrink-0" />
              ) : i === currentIndex ? (
                <Loader2 className="w-4 h-4 animate-spin shrink-0" />
              ) : (
                <div className="w-4 h-4 rounded-full border-2 border-gray-200 shrink-0" />
              )}
              <span className={i === currentIndex ? 'font-medium' : ''}>{s.label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

export default function ChatPage() {
  const [messages, setMessages] = useState([]);
  const [input, setInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [activeMember, setActiveMember] = useState(null);
  const [streamingText, setStreamingText] = useState('');
  const [thinkingStage, setThinkingStage] = useState('fetching');
  const [sections, setSections] = useState({});
  const [agentcoreSessionId] = useState(() => `agentcore-session-${Date.now()}-${Math.random().toString(36).slice(2, 11)}`);
  const bottomRef = useRef(null);
  const sendingRef = useRef(false);
  const accumulatorRef = useRef('');
  const sectionsRef = useRef({});
  const [searchParams, setSearchParams] = useSearchParams();

  // Keep ref in sync with state for use in callbacks
  useEffect(() => { sectionsRef.current = sections; }, [sections]);

  useEffect(() => { bottomRef.current?.scrollIntoView({ behavior: 'smooth' }); }, [messages, loading, sections, streamingText]);

  // Register WebSocket message handler
  useEffect(() => {
    onChatMessage((msg) => {
      switch (msg.type) {
        case 'status':
          setThinkingStage(msg.stage || 'fetching');
          break;

        case 'chunk':
          accumulatorRef.current += msg.content;
          // Try to parse as structured JSON for initial analysis
          tryParseIncrementalJSON(accumulatorRef.current, setSections);
          // Also show raw streaming text for conversational follow-ups
          setStreamingText(accumulatorRef.current);
          setLoading(false);
          break;

        case 'section':
          // Structured section from backend (legacy support)
          setLoading(false);
          setSections(prev => ({ ...prev, [msg.field]: msg.value }));
          break;

        case 'done': {
          const finalText = accumulatorRef.current;
          accumulatorRef.current = '';
          setStreamingText('');
          setLoading(false);
          // Merge any remaining sections into the final message
          const currentSections = sectionsRef.current;
          setMessages(prev => [...prev, {
            role: 'agent',
            text: finalText,
            meta: msg.meta || {},
            sections: { ...currentSections }
          }]);
          setSections({});
          break;
        }

        case 'error':
          accumulatorRef.current = '';
          setStreamingText('');
          setLoading(false);
          setSections({});
          setMessages(prev => [...prev, { role: 'system', text: 'Error: ' + (msg.message || 'Unknown error') }]);
          break;
      }
    });

    return () => {
      onChatMessage(null);
    };
  }, []);

  // Auto-send when navigated from member profile
  useEffect(() => {
    const memberId = searchParams.get('memberId');
    if (memberId && !sendingRef.current) {
      sendingRef.current = true;
      setSearchParams({}, { replace: true });
      setActiveMember(memberId);
      const msg = `Tell me about ${memberId}`;
      setMessages(prev => [...prev, { role: 'user', text: msg }]);
      setLoading(true);
      setThinkingStage('fetching');
      setSections({});
      accumulatorRef.current = '';

      const ws = getWebSocket();
      if (ws && ws.readyState === WebSocket.OPEN) {
        sendChatMessage(ws, memberId, msg);
      } else {
        setLoading(false);
        setMessages(prev => [...prev, { role: 'system', text: 'WebSocket not connected. Please try again.' }]);
      }
      sendingRef.current = false;
    }
  }, [searchParams, setSearchParams]);

  function handleSend(e) {
    e.preventDefault();
    if (!input.trim() || loading || streamingText) return;
    const msg = input.trim();
    setInput('');

    const ws = getWebSocket();
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      setMessages(prev => [...prev, { role: 'system', text: 'WebSocket not connected. Please try again.' }]);
      return;
    }

    setMessages(prev => [...prev, { role: 'user', text: msg }]);
    setLoading(true);
    setThinkingStage('fetching');
    setSections({});
    accumulatorRef.current = '';
    sendChatMessage(ws, '', msg, agentcoreSessionId, 'agentcore');
  }

  return (
    <div className="h-screen flex flex-col">
      {/* Header */}
      <div className="border-b border-gray-200 bg-white px-6 py-4 flex items-center justify-between shrink-0">
        <div>
          <h1 className="text-lg font-bold text-gray-900">AI Care Agent</h1>
          <p className="text-sm text-gray-500">Ask about any member by name — powered by AgentCore</p>
        </div>
        <span className="px-3 py-1.5 bg-purple-100 text-purple-700 rounded-full text-xs font-semibold flex items-center gap-1.5">
          <Cpu className="w-3.5 h-3.5" /> AgentCore
        </span>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-6 space-y-5">
        {messages.length === 0 && !loading && (
          <div className="flex flex-col items-center justify-center h-full text-gray-400">
            <div className="w-20 h-20 rounded-full flex items-center justify-center mb-4 bg-purple-50">
              <Cpu className="w-10 h-10 text-purple-300" />
            </div>
            <p className="text-lg font-medium text-gray-500">How can I help you today?</p>
            <p className="text-sm mt-1">Ask by name: "Tell me about John Smith" or "What are his conditions?"</p>
            <div className="flex gap-2 mt-4 flex-wrap">
              {['Tell me about John Smith', 'Who are the high risk members?', 'Show me Maria Garcia medications'].map(q => (
                <button key={q} onClick={() => { setInput(q); }}
                  className="px-3 py-1.5 bg-white border border-gray-200 rounded-full text-xs text-gray-600 hover:border-purple-300 hover:text-purple-600 transition">
                  {q}
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((msg, i) => (
          <div key={i} className={`flex gap-3 ${msg.role === 'user' ? 'justify-end' : ''}`}>
            {msg.role !== 'user' && (
              <div className={`w-8 h-8 rounded-full flex items-center justify-center shrink-0 mt-1 ${
                msg.role === 'agent' ? 'bg-blue-100 text-blue-600' : 'bg-yellow-100 text-yellow-600'
              }`}>
                {msg.role === 'agent' ? <Bot className="w-4 h-4" /> : <AlertTriangle className="w-4 h-4" />}
              </div>
            )}
            <div className={`rounded-2xl px-5 py-4 ${
              msg.role === 'user' ? 'bg-blue-600 text-white max-w-lg' :
              msg.role === 'agent' ? 'bg-white border border-gray-200 shadow-sm max-w-3xl w-full' :
              'bg-yellow-50 border border-yellow-200 max-w-lg'
            }`}>
              {msg.role === 'agent' && msg.meta && (
                <div className="flex flex-wrap gap-2 mb-3 pb-3 border-b border-gray-100">
                  {msg.meta.memberName && (
                    <span className="text-xs bg-blue-100 text-blue-700 px-2 py-1 rounded-full font-semibold">{msg.meta.memberName}</span>
                  )}
                  {msg.meta.memberId && (
                    <span className="text-xs bg-gray-100 text-gray-600 px-2 py-1 rounded-full font-medium">{msg.meta.memberId}</span>
                  )}
                  {msg.meta.careGaps > 0 && (
                    <span className="flex items-center gap-1 text-xs text-red-600 bg-red-50 px-2 py-1 rounded-full font-medium">
                      <AlertTriangle className="w-3 h-3" /> {msg.meta.careGaps} care gaps
                    </span>
                  )}
                  {msg.meta.interventions > 0 && (
                    <span className="flex items-center gap-1 text-xs text-green-600 bg-green-50 px-2 py-1 rounded-full font-medium">
                      <CheckCircle className="w-3 h-3" /> {msg.meta.interventions} actions
                    </span>
                  )}
                  {msg.meta.cached && (
                    <span className="text-xs text-gray-400 bg-gray-50 px-2 py-1 rounded-full">cached</span>
                  )}
                </div>
              )}
              {msg.role === 'agent' ? (
                <AgentResponse text={msg.text} meta={msg.meta} isStreaming={false} streamingSections={msg.sections} />
              ) : (
                <p className="text-sm leading-relaxed">{msg.text}</p>
              )}
            </div>
            {msg.role === 'user' && (
              <div className="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center shrink-0 mt-1">
                <User className="w-4 h-4 text-gray-600" />
              </div>
            )}
          </div>
        ))}

        {/* Streaming sections — cards appear as each section arrives (initial analysis) */}
        {Object.keys(sections).length > 0 && (
          <div className="flex gap-3">
            <div className="w-8 h-8 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center shrink-0 mt-1">
              <Bot className="w-4 h-4" />
            </div>
            <div className="bg-white border border-gray-200 shadow-sm max-w-3xl w-full rounded-2xl px-5 py-4">
              <AgentResponse text="" meta={{}} isStreaming={false} streamingSections={sections} />
            </div>
          </div>
        )}

        {/* Streaming text — for conversational follow-up responses or AgentCore */}
        {streamingText && Object.keys(sections).length === 0 && (
          <div className="flex gap-3">
            <div className="w-8 h-8 rounded-full flex items-center justify-center shrink-0 mt-1 bg-purple-100 text-purple-600">
              <Cpu className="w-4 h-4" />
            </div>
            <div className="bg-white border border-gray-200 shadow-sm max-w-3xl w-full rounded-2xl px-5 py-4">
              <MarkdownText text={streamingText} isStreaming={true} />
            </div>
          </div>
        )}

        {loading && <ThinkingIndicator stage={thinkingStage} />}
        <div ref={bottomRef} />
      </div>

      {/* Input */}
      <form onSubmit={handleSend} className="border-t border-gray-200 bg-white p-4 shrink-0">
        <div className="flex gap-3 max-w-4xl mx-auto">
          <input value={input} onChange={e => setInput(e.target.value)}
            placeholder="Ask about any member by name... (e.g., Tell me about John Smith)"
            className="flex-1 px-4 py-3 rounded-xl border border-gray-200 focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none text-sm"
            disabled={loading || !!streamingText} />
          <button type="submit" disabled={loading || !!streamingText || !input.trim()}
            className="px-5 py-3 bg-blue-600 hover:bg-blue-700 text-white rounded-xl transition disabled:opacity-50 flex items-center gap-2 text-sm font-medium">
            <Send className="w-4 h-4" /> Send
          </button>
        </div>
      </form>
    </div>
  );
}
