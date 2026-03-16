#!/usr/bin/env ruby
# ASC APIで審査連絡先を設定するスクリプト
require 'net/http'
require 'json'
require 'openssl'
require 'base64'

KEY_ID    = "HQ762J84KW"
ISSUER_ID = "f4fe1f90-e544-4676-afe7-207553e56612"
KEY_PATH  = File.expand_path("~/Downloads/AuthKey_HQ762J84KW.p8")
APP_ID_BUNDLE = "com.tkysdev.customsoundalarm"

key = OpenSSL::PKey.read(File.read(KEY_PATH))

def jwt(key, key_id, issuer_id)
  def rs(d)
    a = OpenSSL::ASN1.decode(d)
    r = a.value[0].value.to_s(2).rjust(32,"\x00")[-32..]
    s = a.value[1].value.to_s(2).rjust(32,"\x00")[-32..]
    Base64.urlsafe_encode64(r+s, padding:false)
  end
  now = Time.now.to_i
  h = Base64.urlsafe_encode64(JSON.generate({alg:"ES256",kid:key_id,typ:"JWT"}), padding:false)
  p = Base64.urlsafe_encode64(JSON.generate({iss:issuer_id,iat:now,exp:now+1200,aud:"appstoreconnect-v1"}), padding:false)
  si = "#{h}.#{p}"
  "#{si}.#{rs(key.sign(OpenSSL::Digest::SHA256.new, si))}"
end

token = jwt(key, KEY_ID, ISSUER_ID)
http = Net::HTTP.new("api.appstoreconnect.apple.com", 443)
http.use_ssl = true

def call(http, method, path, token, body=nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  r = Object.const_get("Net::HTTP::#{method}").new(uri)
  r["Authorization"] = "Bearer #{token}"
  r["Content-Type"]  = "application/json"
  r.body = JSON.generate(body) if body
  resp = http.request(r)
  puts "#{method} #{path} => #{resp.code}"
  JSON.parse(resp.body) rescue {}
end

# 1. APP IDを取得
apps = call(http, "Get", "/v1/apps?filter[bundleId]=#{APP_ID_BUNDLE}", token)
app_id = apps.dig("data", 0, "id")
puts "App ID: #{app_id}"

# 2. バージョンIDを取得
versions = call(http, "Get", "/v1/apps/#{app_id}/appStoreVersions?filter[appStoreState]=PREPARE_FOR_SUBMISSION", token)
version_id = versions.dig("data", 0, "id")
puts "Version ID: #{version_id}"

# 3. 審査連絡先を設定
result = call(http, "Post", "/v1/appStoreReviewDetails", token, {
  data: {
    type: "appStoreReviewDetails",
    attributes: {
      contactFirstName: "Takuya",
      contactLastName: "S",
      contactPhone: "+81 90 0000 0000",
      contactEmail: "tkysdev@gmail.com",
      demoAccountRequired: false,
      notes: "No login required. The app allows users to set custom alarm sounds from imported audio files and videos."
    },
    relationships: {
      appStoreVersion: { data: { type: "appStoreVersions", id: version_id } }
    }
  }
})
puts JSON.pretty_generate(result)

# 4. 年齢制限を4+に設定
infos = call(http, "Get", "/v1/apps/#{app_id}/appInfos", token)
info_id = infos.dig("data", 0, "id")
puts "AppInfo ID: #{info_id}"

ar = call(http, "Get", "/v1/appInfos/#{info_id}/ageRatingDeclaration", token)
ar_id = ar.dig("data", "id")
puts "AgeRating ID: #{ar_id}"

if ar_id
  age_result = call(http, "Patch", "/v1/ageRatingDeclarations/#{ar_id}", token, {
    data: {
      type: "ageRatingDeclarations", id: ar_id,
      attributes: {
        gambling: false,
        lootBox: false,
        unrestrictedWebAccess: false,
        alcoholTobaccoOrDrugUseOrReferences: "NONE",
        contests: "NONE",
        gamblingSimulated: "NONE",
        gunsOrOtherWeapons: "NONE",
        horrorOrFearThemes: "NONE",
        matureOrSuggestiveThemes: "NONE",
        medicalOrTreatmentInformation: "NONE",
        profanityOrCrudeHumor: "NONE",
        sexualContentGraphicAndNudity: "NONE",
        sexualContentOrNudity: "NONE",
        violenceCartoonOrFantasy: "NONE",
        violenceRealistic: "NONE",
        violenceRealisticProlongedGraphicOrSadistic: "NONE"
      }
    }
  })
  puts "Age rating: #{age_result.dig("data", "attributes", "ageRatingOverride") || "set"}"
end

puts "\nDone! Check App Store Connect."
