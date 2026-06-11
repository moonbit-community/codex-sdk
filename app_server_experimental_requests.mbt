// Copyright 2026 International Digital Economy Academy
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

///|
pub(all) enum AppRealtimeOutputModality {
  AppRealtimeText
  AppRealtimeAudio
} derive(Debug)

///|
pub impl ToJson for AppRealtimeOutputModality with fn to_json(modality) {
  match modality {
    AppRealtimeText => "text".to_json()
    AppRealtimeAudio => "audio".to_json()
  }
}

///|
pub(all) enum AppRealtimeVoice {
  AppRealtimeVoiceAlloy
  AppRealtimeVoiceArbor
  AppRealtimeVoiceAsh
  AppRealtimeVoiceBallad
  AppRealtimeVoiceBreeze
  AppRealtimeVoiceCedar
  AppRealtimeVoiceCoral
  AppRealtimeVoiceCove
  AppRealtimeVoiceEcho
  AppRealtimeVoiceEmber
  AppRealtimeVoiceJuniper
  AppRealtimeVoiceMaple
  AppRealtimeVoiceMarin
  AppRealtimeVoiceSage
  AppRealtimeVoiceShimmer
  AppRealtimeVoiceSol
  AppRealtimeVoiceSpruce
  AppRealtimeVoiceVale
  AppRealtimeVoiceVerse
} derive(Debug)

///|
pub impl ToJson for AppRealtimeVoice with fn to_json(voice) {
  match voice {
    AppRealtimeVoiceAlloy => "alloy".to_json()
    AppRealtimeVoiceArbor => "arbor".to_json()
    AppRealtimeVoiceAsh => "ash".to_json()
    AppRealtimeVoiceBallad => "ballad".to_json()
    AppRealtimeVoiceBreeze => "breeze".to_json()
    AppRealtimeVoiceCedar => "cedar".to_json()
    AppRealtimeVoiceCoral => "coral".to_json()
    AppRealtimeVoiceCove => "cove".to_json()
    AppRealtimeVoiceEcho => "echo".to_json()
    AppRealtimeVoiceEmber => "ember".to_json()
    AppRealtimeVoiceJuniper => "juniper".to_json()
    AppRealtimeVoiceMaple => "maple".to_json()
    AppRealtimeVoiceMarin => "marin".to_json()
    AppRealtimeVoiceSage => "sage".to_json()
    AppRealtimeVoiceShimmer => "shimmer".to_json()
    AppRealtimeVoiceSol => "sol".to_json()
    AppRealtimeVoiceSpruce => "spruce".to_json()
    AppRealtimeVoiceVale => "vale".to_json()
    AppRealtimeVoiceVerse => "verse".to_json()
  }
}

///|
pub impl FromJson for AppRealtimeVoice with fn from_json(value, path) {
  match value {
    String("alloy") => AppRealtimeVoiceAlloy
    String("arbor") => AppRealtimeVoiceArbor
    String("ash") => AppRealtimeVoiceAsh
    String("ballad") => AppRealtimeVoiceBallad
    String("breeze") => AppRealtimeVoiceBreeze
    String("cedar") => AppRealtimeVoiceCedar
    String("coral") => AppRealtimeVoiceCoral
    String("cove") => AppRealtimeVoiceCove
    String("echo") => AppRealtimeVoiceEcho
    String("ember") => AppRealtimeVoiceEmber
    String("juniper") => AppRealtimeVoiceJuniper
    String("maple") => AppRealtimeVoiceMaple
    String("marin") => AppRealtimeVoiceMarin
    String("sage") => AppRealtimeVoiceSage
    String("shimmer") => AppRealtimeVoiceShimmer
    String("sol") => AppRealtimeVoiceSol
    String("spruce") => AppRealtimeVoiceSpruce
    String("vale") => AppRealtimeVoiceVale
    String("verse") => AppRealtimeVoiceVerse
    _ => raise JsonDecodeError((path, "expected realtime voice"))
  }
}

///|
pub(all) struct AppRealtimeVoicesList {
  v1 : ArrayView[AppRealtimeVoice]
  v2 : ArrayView[AppRealtimeVoice]
  default_v1 : AppRealtimeVoice
  default_v2 : AppRealtimeVoice
} derive(Debug)

///|
pub impl FromJson for AppRealtimeVoicesList with fn from_json(value, path) {
  guard value
    is {
      "v1": v1,
      "v2": v2,
      "defaultV1": default_v1,
      "defaultV2": default_v2,
      ..
    } else {
    raise JsonDecodeError((path, "expected realtime voices list"))
  }
  {
    v1: @json.from_json(v1, path=path.add_key("v1")),
    v2: @json.from_json(v2, path=path.add_key("v2")),
    default_v1: @json.from_json(default_v1, path=path.add_key("defaultV1")),
    default_v2: @json.from_json(default_v2, path=path.add_key("defaultV2")),
  }
}

///|
pub(all) enum AppThreadRealtimeStartTransport {
  AppThreadRealtimeWebsocket
  AppThreadRealtimeWebrtc(sdp~ : String)
} derive(Debug)

///|
pub impl ToJson for AppThreadRealtimeStartTransport with fn to_json(transport) {
  match transport {
    AppThreadRealtimeWebsocket => { "type": "websocket" }
    AppThreadRealtimeWebrtc(sdp~) => { "type": "webrtc", "sdp": sdp }
  }
}

///|
pub(all) struct AppThreadRealtimeStartParams {
  thread_id : String
  output_modality : AppRealtimeOutputModality
  prompt : AppNullableString?
  realtime_session_id : String?
  transport : AppThreadRealtimeStartTransport?
  voice : AppRealtimeVoice?
} derive(Debug)

///|
pub impl ToJson for AppThreadRealtimeStartParams with fn to_json(params) {
  let obj : Map[String, Json] = {
    "threadId": params.thread_id,
    "outputModality": params.output_modality,
    "realtimeSessionId": match params.realtime_session_id {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "transport": match params.transport {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "voice": match params.voice {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
  app_put_nullable_string(obj, "prompt", params.prompt)
  Json::object(obj)
}

///|
pub impl ToJson for AppThreadRealtimeAudioChunk with fn to_json(audio) {
  let obj : Map[String, Json] = {
    "data": audio.data,
    "sampleRate": audio.sample_rate,
    "numChannels": audio.num_channels,
    "samplesPerChannel": match audio.samples_per_channel {
      Some(value) => value.to_json()
      None => Json::null()
    },
    "itemId": match audio.item_id {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
  Json::object(obj)
}

///|
pub(all) struct AppThreadRealtimeAppendAudioParams {
  thread_id : String
  audio : AppThreadRealtimeAudioChunk
} derive(Debug)

///|
pub impl ToJson for AppThreadRealtimeAppendAudioParams with fn to_json(params) {
  { "threadId": params.thread_id, "audio": params.audio }
}

///|
pub(all) struct AppThreadRealtimeAppendTextParams {
  thread_id : String
  text : String
} derive(Debug)

///|
pub impl ToJson for AppThreadRealtimeAppendTextParams with fn to_json(params) {
  { "threadId": params.thread_id, "text": params.text }
}

///|
pub(all) struct AppThreadRealtimeListVoicesResponse {
  voices : AppRealtimeVoicesList
} derive(Debug)

///|
pub impl FromJson for AppThreadRealtimeListVoicesResponse with fn from_json(
  value,
  path,
) {
  guard value is { "voices": voices, .. } else {
    raise JsonDecodeError(
      (path, "expected thread/realtime/listVoices response"),
    )
  }
  { voices: @json.from_json(voices, path=path.add_key("voices")) }
}

///|
pub(all) enum AppCollaborationModeKind {
  AppCollaborationPlan
  AppCollaborationDefault
} derive(Debug)

///|
pub impl FromJson for AppCollaborationModeKind with fn from_json(value, path) {
  match value {
    String("plan") => AppCollaborationPlan
    String("default") => AppCollaborationDefault
    _ => raise JsonDecodeError((path, "expected collaboration mode kind"))
  }
}

///|
pub(all) struct AppCollaborationModeMask {
  name : String
  mode : AppCollaborationModeKind?
  model : String?
  reasoning_effort : AppReasoningEffort?
} derive(Debug)

///|
pub impl FromJson for AppCollaborationModeMask with fn from_json(value, path) {
  guard value
    is {
      "name": String(name),
      "mode"? : mode,
      "model"? : model,
      "reasoning_effort"? : reasoning_effort,
      ..
    } else {
    raise JsonDecodeError((path, "expected collaboration mode mask"))
  }
  {
    name,
    mode: match mode {
      Some(Null) | None => None
      Some(value) => Some(@json.from_json(value, path=path.add_key("mode")))
    },
    model: app_optional_string(model, path.add_key("model")),
    reasoning_effort: match reasoning_effort {
      Some(Null) | None => None
      Some(value) =>
        Some(@json.from_json(value, path=path.add_key("reasoning_effort")))
    },
  }
}

///|
pub(all) struct AppCollaborationModeListResponse {
  data : ArrayView[AppCollaborationModeMask]
} derive(Debug)

///|
pub impl FromJson for AppCollaborationModeListResponse with fn from_json(
  value,
  path,
) {
  guard value is { "data": data, .. } else {
    raise JsonDecodeError((path, "expected collaborationMode/list response"))
  }
  { data: @json.from_json(data, path=path.add_key("data")) }
}

///|
pub(all) struct AppMockExperimentalMethodParams {
  value : String?
} derive(Debug)

///|
pub impl ToJson for AppMockExperimentalMethodParams with fn to_json(params) {
  {
    "value": match params.value {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
}

///|
pub(all) struct AppMockExperimentalMethodResponse {
  echoed : String?
} derive(Debug)

///|
pub impl FromJson for AppMockExperimentalMethodResponse with fn from_json(
  value,
  path,
) {
  guard value is { "echoed"? : echoed, .. } else {
    raise JsonDecodeError((path, "expected mock/experimentalMethod response"))
  }
  { echoed: app_optional_string(echoed, path.add_key("echoed")) }
}

///|
pub(all) struct AppFuzzyFileSearchSessionStartParams {
  session_id : String
  roots : Array[String]
} derive(Debug)

///|
pub impl ToJson for AppFuzzyFileSearchSessionStartParams with fn to_json(params) {
  { "sessionId": params.session_id, "roots": params.roots }
}

///|
pub(all) struct AppFuzzyFileSearchSessionUpdateParams {
  session_id : String
  query : String
} derive(Debug)

///|
pub impl ToJson for AppFuzzyFileSearchSessionUpdateParams with fn to_json(
  params,
) {
  { "sessionId": params.session_id, "query": params.query }
}

///|
pub(all) struct AppFuzzyFileSearchSessionStopParams {
  session_id : String
} derive(Debug)

///|
pub impl ToJson for AppFuzzyFileSearchSessionStopParams with fn to_json(params) {
  { "sessionId": params.session_id }
}

///|
pub async fn CodexAppConnection::thread_realtime_start(
  self : CodexAppConnection,
  params : AppThreadRealtimeStartParams,
) -> Unit {
  self.call_empty("thread/realtime/start", params=params.to_json())
}

///|
pub async fn CodexAppConnection::thread_realtime_append_audio(
  self : CodexAppConnection,
  params : AppThreadRealtimeAppendAudioParams,
) -> Unit {
  self.call_empty("thread/realtime/appendAudio", params=params.to_json())
}

///|
pub async fn CodexAppConnection::thread_realtime_append_text(
  self : CodexAppConnection,
  params : AppThreadRealtimeAppendTextParams,
) -> Unit {
  self.call_empty("thread/realtime/appendText", params=params.to_json())
}

///|
pub async fn CodexAppConnection::thread_realtime_stop(
  self : CodexAppConnection,
  params : AppThreadIdParams,
) -> Unit {
  self.call_empty("thread/realtime/stop", params=params.to_json())
}

///|
pub async fn CodexAppConnection::thread_realtime_list_voices(
  self : CodexAppConnection,
) -> AppThreadRealtimeListVoicesResponse {
  @json.from_json(self.call_raw("thread/realtime/listVoices", params={}))
}

///|
pub async fn CodexAppConnection::collaboration_mode_list(
  self : CodexAppConnection,
) -> AppCollaborationModeListResponse {
  @json.from_json(self.call_raw("collaborationMode/list", params={}))
}

///|
pub async fn CodexAppConnection::mock_experimental_method(
  self : CodexAppConnection,
  params : AppMockExperimentalMethodParams,
) -> AppMockExperimentalMethodResponse {
  @json.from_json(
    self.call_raw("mock/experimentalMethod", params=params.to_json()),
  )
}

///|
pub async fn CodexAppConnection::fuzzy_file_search_session_start(
  self : CodexAppConnection,
  params : AppFuzzyFileSearchSessionStartParams,
) -> Unit {
  self.call_empty("fuzzyFileSearch/sessionStart", params=params.to_json())
}

///|
pub async fn CodexAppConnection::fuzzy_file_search_session_update(
  self : CodexAppConnection,
  params : AppFuzzyFileSearchSessionUpdateParams,
) -> Unit {
  self.call_empty("fuzzyFileSearch/sessionUpdate", params=params.to_json())
}

///|
pub async fn CodexAppConnection::fuzzy_file_search_session_stop(
  self : CodexAppConnection,
  params : AppFuzzyFileSearchSessionStopParams,
) -> Unit {
  self.call_empty("fuzzyFileSearch/sessionStop", params=params.to_json())
}
