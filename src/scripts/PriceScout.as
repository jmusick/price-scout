package
{
   import flash.display.MovieClip;
   import flash.display.Shape;
   import flash.events.Event;
   import flash.events.TimerEvent;
   import flash.filters.GlowFilter;
   import flash.text.AntiAliasType;
   import flash.text.TextField;
   import flash.text.TextFieldAutoSize;
   import flash.text.TextFormat;
   import flash.utils.Timer;
   import flash.utils.getDefinitionByName;
   import flash.utils.getQualifiedClassName;
   import flash.utils.getTimer;

   // PriceScout test build: a HUDModLoader child SWF that listens to the game's vendor
   // data providers from inside HUDMenu and records other players' vending prices.
   //
   // Files it writes through xScal modStorage (Data\modsdata\):
   //   pricescout_history.json  prices seen, per item key (same key as Better Containers)
   //   pricescout_diag.json     what the providers sent, for working out the data shape
   public class PriceScout extends MovieClip
   {
      public static const BUILD:String = "0.9.1";

      private static const HISTORY_STORE:String = "pricescout_history";
      private static const DIAG_STORE:String = "pricescout_diag";
      private static const SETTINGS_STORE:String = "pricescout_settings";
      // Market-price mode prices an item with no market price at its item value plus this
      // percentage, unless pricescout_settings.json says otherwise.
      private static const DEFAULT_NO_MARKET_MARKUP:Number = 30;

      // Better Containers' remembered sale prices: name|level|stars -> price. Its Sale
      // Planner pre-fills a remembered price when you list an item. PriceScout adds its
      // suggestion for items you have not priced, and records what it wrote in FEED_STORE
      // so it only ever updates its own values, never yours.
      private static const BC_STORE:String = "bettercontainers_vendorprices";
      private static const FEED_STORE:String = "pricescout_bcfeed";
      private static const FEED_MIN_VENDORS:int = 2;
      private static const BC_MAX_PRICE:int = 40000;
      private static const BC_REREAD_MS:int = 2000;
      // Recorded in feedWritten for a key whose remembered price market-price mode removed.
      private static const REMOVED:int = -1;

      // Market-price mode hotkey (F10) and Better Containers' Vendor manager key (M), as
      // Windows virtual-key codes for xScal's Input.RegisterKey / IsKeyPressed.
      private static const MODE_KEY:int = 0x79;
      private static const MANAGER_KEY:int = 77;
      // In market-price mode, prices are applied once your machine's stash list arrives,
      // or after this long if it does not.
      private static const MARKET_APPLY_WAIT_MS:int = 2500;

      private static const MAX_LEGENDARY_SAMPLES:int = 5;

      private static const TYPE_PROVIDER:String = "OtherInventoryTypeData";
      private static const INVENTORY_PROVIDER:String = "OtherInventoryData";
      // Items in someone else's camp vending machine (menuType 3) arrive here, not in
      // OtherInventoryData, which is empty for those machines.
      private static const OFFERS_PROVIDER:String = "CampVendingOfferData";
      private static const CONTROL_PROVIDER:String = "PlayerInventoryData";
      // hudMode is "All" in normal play and changes when the Pip-Boy, a container or vendor,
      // the map and so on are open. The status line shows only in the modes listed here.
      private static const HUD_MODE_PROVIDER:String = "HUDModeData";
      private static const STATUS_HUD_MODES:Array = ["All","PowerArmor","ActivateTypeMode","CrosshairAndActivateOnly"];
      // The game publishes the highlighted item here (serverHandleID) when a menu selects it.
      private static const CARD_PROVIDER:String = "InventoryItemCardData";

      private static const MODE_PLAYERVENDING:uint = 1;
      private static const MODE_NPCVENDING:uint = 2;
      private static const MODE_VENDING_MACHINE:uint = 3;
      private static const MACHINE_TYPE_VENDING:uint = 1;

      private static const MAX_PER_ITEM:int = 200;
      private static const MAX_ERRORS:int = 20;
      private static const MAX_LOG:int = 60;
      private static const REWATCH_MIN_MS:int = 1000;
      private static const CODE_OBJECT_WAIT_FRAMES:int = 1800;
      private static const SAVE_INTERVAL_MS:int = 3000;
      private static const DAY_SECONDS:Number = 86400;

      private static const STATUS_FONT:String = "$MAIN_Font_Bold";
      private static const STATUS_X:Number = 40;
      private static const STATUS_Y:Number = 140;
      private static const STATUS_PAD:Number = 6;

      // Suggestion rules, the same as tools/report.py.
      private static const SUGGEST_DAYS:Number = 30;
      // Characters quote() must escape in JSON: quote, backslash and control characters.
      private static const NEEDS_ESCAPE:RegExp = /["\\\x00-\x1f]/;

      // History older than this is dropped at login.
      private static const HISTORY_KEEP_DAYS:Number = 60;
      private static const PLACEHOLDER_PRICE:Number = 40000;
      // The market price deals are measured against: the lower quartile of vendors'
      // prices. Asking prices lean high, since cheap listings sell and expensive ones stay
      // up. The selling price is set by sellMethod, and is this same quartile by default.
      private static const MARKET_QUANTILE:Number = 0.25;
      // Selling price methods (pricescout_settings.json "sellMethod"):
      //   percentile    the sellPercentile percentile of vendors' prices (default 25)
      //   undercut      the cheapest vendor's price less undercutPercent
      //   fencedMedian  the median, leaving out prices outside Tukey's fences (1.5 IQR)
      private static const METHOD_PERCENTILE:String = "percentile";
      private static const METHOD_UNDERCUT:String = "undercut";
      private static const METHOD_FENCED_MEDIAN:String = "fencedMedian";
      private static const DEFAULT_SELL_PERCENTILE:Number = 25;
      private static const DEFAULT_UNDERCUT_PERCENT:Number = 5;
      private static const TUKEY_K:Number = 1.5;
      // Fewer vendors than this is one person's price, not a market: never fed or used in
      // market-price mode (which sets 0 instead), and shown dimmed.
      private static const MARKET_MIN_VENDORS:int = 2;

      // Price panel: centred under the vendor menu, growing upward from PANEL_BOTTOM, in
      // HUD coordinates (1920x1080).
      private static const PANEL_CENTER_X:Number = 960;
      private static const PANEL_BOTTOM:Number = 1066;
      private static const PANEL_PAD_X:Number = 14;
      private static const PANEL_PAD_Y:Number = 7;
      private static const PANEL_LINE_GAP:Number = 4;
      private static const PANEL_ALPHA:Number = 0.82;
      private static const ITEM_NAME_LENGTH:int = 40;
      private static const DEAL_NAME_LENGTH:int = 26;

      // Better Containers' palette, so the panel matches the menu above it.
      private static const COLOR_TEXT:uint = 0xFFFFCA;
      private static const COLOR_DIM:uint = 0xDCCB9B;
      private static const COLOR_ACCENT:uint = 0xF5CB5B;
      private static const COLOR_GOOD:uint = 0x55FC42;
      private static const COLOR_BAD:uint = 0xFC4442;
      private static const COLOR_PANEL:uint = 0x080A0D;

      // Best deals: items at least DEAL_MIN_PERCENT below the market price (lower quartile)
      // of DEAL_MIN_VENDORS or more other vendors; the DEALS_SHOWN cheapest relative to market are listed.
      private static const DEAL_MIN_VENDORS:int = 2;
      private static const DEAL_MIN_PERCENT:int = 10;
      private static const DEALS_SHOWN:int = 3;

      // HUDModLoader reads this from the loaded content.
      public var isReloadable:Boolean = false;

      private var topLevel:Object;
      private var dataManager:Object;
      private var codeObj:Object;
      private var waitFrames:int = 0;

      private var history:Object = {};
      private var historyLoaded:Boolean = false;
      private var historySaveBlocked:Boolean = false;
      private var historyDirty:Boolean = false;
      private var diagDirty:Boolean = false;
      private var saveTimer:Timer;

      private var typeData:Object;
      private var inventoryData:Object;
      private var offersData:Object;
      private var playerData:Object;
      private var cardHandle:Number = 0;
      private var cardText:String;
      private var cardData:Object;
      private var feedWritten:Object = {};
      private var feedPending:Boolean = false;
      private var feedStale:Boolean = false;
      private var historyVersion:int = 0;
      private var dealsFor:String;
      private var dealsLine:Array;
      private var bcPrices:Object;
      private var bcPricesAt:int = 0;
      private var bcText:String;
      private var feedOriginals:Object = {};
      private var ownedValues:Object = {};
      private var marketMode:Boolean = false;
      private var keysRegistered:Boolean = false;
      private var modeKeyDown:Boolean = false;
      private var managerKeyDown:Boolean = false;
      private var managerOpenedThisVisit:Boolean = false;
      private var visitApplied:Boolean = false;
      private var appliedAfterManager:Boolean = false;
      private var ownedStashSeen:Boolean = false;
      private var visitStartedAt:int = 0;
      private var lastVendor:String;
      private var rewatching:Boolean = false;
      private var lastRewatch:Object = {};
      private var listOwners:Object = {};
      private var hudMode:String;
      private var panelBox:Shape;
      private var panelFields:Array = [];
      private var diag:Object;
      private var fullDiagnostics:Boolean = false;
      private var noMarketMarkup:Number = DEFAULT_NO_MARKET_MARKUP;
      private var sellMethod:String = METHOD_PERCENTILE;
      private var sellPercentile:Number = DEFAULT_SELL_PERCENTILE;
      private var undercutPercent:Number = DEFAULT_UNDERCUT_PERCENT;
      // How many vendors' worth of weight the item value (+noMarketMarkup) gets when
      // blended into the selling price; 0 turns blending off.
      private var itemValueWeight:Number = 0;
      private var diagMustSave:Boolean = false;
      private var status:TextField;
      private var statusFormat:TextFormat;
      private var statusBox:Shape;

      private var jsonText:String;
      private var jsonPos:int;
      private var jsonBackslash:int = -1;

      public function PriceScout()
      {
         super();
         this.diag = {
            "build":BUILD,
            "startedAt":nowSeconds(),
            "hudMenu":false,
            "dataManager":"not tried",
            "codeObject":"waiting",
            "historyLoad":"not tried",
            "subscribe":{},
            "events":{},
            "recorded":0,
            "skipped":{},
            "lastType":null,
            "lastInventory":null,
            "lastOffers":null,
            "lastRecorded":[],
            "rewatches":0,
            "eventLog":[],
            "errors":[]
         };
         addEventListener(Event.ADDED_TO_STAGE,this.onAddedToStage);
      }

      private function onAddedToStage(e:Event) : void
      {
         removeEventListener(Event.ADDED_TO_STAGE,this.onAddedToStage);
         this.createStatus();
         try
         {
            this.topLevel = stage.getChildAt(0);
            this.diag.hudMenu = this.topLevel != null && getQualifiedClassName(this.topLevel) == "HUDMenu";
         }
         catch(error:Error)
         {
            this.addError("stage.getChildAt(0): " + error.message);
         }
         if(this.diag.hudMenu != true)
         {
            this.setStatus("not loaded into HUDMenu");
            return;
         }
         try
         {
            this.dataManager = getDefinitionByName("Shared.AS3.Data.BSUIDataManager");
            this.diag.dataManager = "ok";
         }
         catch(error:Error)
         {
            this.diag.dataManager = "error: " + error.message;
            this.reportFatal("BSUIDataManager not found: " + error.message);
            return;
         }
         this.subscribe(TYPE_PROVIDER);
         this.subscribe(INVENTORY_PROVIDER);
         this.subscribe(OFFERS_PROVIDER);
         this.subscribe(CONTROL_PROVIDER);
         this.subscribe(HUD_MODE_PROVIDER);
         this.subscribe(CARD_PROVIDER);
         this.saveTimer = new Timer(SAVE_INTERVAL_MS);
         this.saveTimer.addEventListener(TimerEvent.TIMER,this.onSaveTimer);
         this.saveTimer.start();
         addEventListener(Event.ENTER_FRAME,this.waitForCodeObject);
         this.updateStatus();
      }

      // ---- Settings ---------------------------------------------------------------------

      // Data\modsdata\pricescout_settings.json, created or completed with the defaults:
      //   "diagnostics": true writes the full diagnostics file (event log, data samples,
      //   legendary item cards, the last vendor's name) instead of a short summary.
      //   "noMarketMarkupPercent": in market-price mode, an item with no market price is
      //   priced at its item value plus this percentage (default 30).
      //   "sellMethod": "percentile" (default), "undercut" or "fencedMedian".
      //   "sellPercentile": the percentile the percentile method uses (default 25).
      //   "undercutPercent": how far below the cheapest vendor undercut goes (default 5).
      //   "itemValueWeight": blends the item value (+noMarketMarkupPercent) into the
      //   selling price as if it were this many vendors (default 0, off).
      private function loadSettings() : void
      {
         var stored:* = undefined;
         var parsed:Object = null;
         var complete:Boolean = false;
         var names:Array = ["diagnostics","noMarketMarkupPercent","sellMethod","sellPercentile","undercutPercent","itemValueWeight"];
         var name:String = null;
         try
         {
            stored = this.codeObj.modStorage.load(SETTINGS_STORE);
            if(stored !== false)
            {
               parsed = this.parseJson(String(stored)) as Object;
            }
            complete = parsed != null;
            for each(name in names)
            {
               complete = complete && parsed[name] !== undefined;
            }
            if(parsed != null)
            {
               this.fullDiagnostics = parsed.diagnostics == true;
               this.noMarketMarkup = settingNumber(parsed.noMarketMarkupPercent,0,Infinity,this.noMarketMarkup);
               if(parsed.sellMethod == METHOD_PERCENTILE || parsed.sellMethod == METHOD_UNDERCUT || parsed.sellMethod == METHOD_FENCED_MEDIAN)
               {
                  this.sellMethod = String(parsed.sellMethod);
               }
               else if(parsed.sellMethod !== undefined)
               {
                  this.addError("settings: unknown sellMethod \"" + parsed.sellMethod + "\", using " + this.sellMethod);
               }
               this.sellPercentile = settingNumber(parsed.sellPercentile,0,100,this.sellPercentile);
               this.undercutPercent = settingNumber(parsed.undercutPercent,0,100,this.undercutPercent);
               this.itemValueWeight = settingNumber(parsed.itemValueWeight,0,Infinity,this.itemValueWeight);
            }
            // Write the file back with every setting, so missing ones appear with defaults.
            // An unknown sellMethod is kept as typed, so a typo can be seen and fixed.
            if(!complete)
            {
               this.codeObj.modStorage.save(SETTINGS_STORE,"{\"version\":1,\"diagnostics\":" + (this.fullDiagnostics ? "true" : "false") + ",\"noMarketMarkupPercent\":" + this.noMarketMarkup + ",\"sellMethod\":" + quote(parsed != null && parsed.sellMethod !== undefined ? String(parsed.sellMethod) : this.sellMethod) + ",\"sellPercentile\":" + this.sellPercentile + ",\"undercutPercent\":" + this.undercutPercent + ",\"itemValueWeight\":" + this.itemValueWeight + "}");
            }
         }
         catch(error:Error)
         {
            this.addError("settings: " + error.message);
         }
         this.diag.diagnostics = this.fullDiagnostics ? "full" : "summary (set \"diagnostics\": true in " + SETTINGS_STORE + ".json for full)";
         this.diag.sellMethod = this.methodText() + (this.itemValueWeight > 0 ? ", item value weight " + this.itemValueWeight : "");
         this.diagMustSave = true;
      }

      // A numeric setting within min..max, or fallback when it is missing or out of range.
      private static function settingNumber(value:*, min:Number, max:Number, fallback:Number) : Number
      {
         if(value === undefined || value === null || isNaN(Number(value)) || Number(value) < min || Number(value) > max)
         {
            return fallback;
         }
         return Number(value);
      }

      private function diagSummary() : Object
      {
         return {
            "build":this.diag.build,
            "diagnostics":this.diag.diagnostics,
            "sellMethod":this.diag.sellMethod,
            "startedAt":this.diag.startedAt,
            "savedAt":this.diag.savedAt,
            "hudMenu":this.diag.hudMenu,
            "dataManager":this.diag.dataManager,
            "codeObject":this.diag.codeObject,
            "historyLoad":this.diag.historyLoad,
            "subscribe":this.diag.subscribe,
            "hotkey":this.diag.hotkey,
            "feed":this.diag.feed,
            "recorded":this.diag.recorded,
            "errors":this.diag.errors
         };
      }

      // ---- xScal storage ------------------------------------------------------------

      private function waitForCodeObject(e:Event) : void
      {
         var candidate:Object = null;
         try
         {
            candidate = this.topLevel.__SFCodeObj;
            if(candidate != null && candidate.modStorage != null && candidate.modStorage.save is Function)
            {
               this.codeObj = candidate;
            }
         }
         catch(error:Error)
         {
            candidate = null;
         }
         if(this.codeObj != null)
         {
            removeEventListener(Event.ENTER_FRAME,this.waitForCodeObject);
            this.diag.codeObject = "ok after " + this.waitFrames + " frames";
            this.loadSettings();
            this.loadHistory();
            addEventListener(Event.ENTER_FRAME,this.pollKeys);
            this.diagDirty = true;
            this.updateStatus();
            return;
         }
         if(++this.waitFrames >= CODE_OBJECT_WAIT_FRAMES)
         {
            removeEventListener(Event.ENTER_FRAME,this.waitForCodeObject);
            this.diag.codeObject = "timeout: no __SFCodeObj.modStorage after " + this.waitFrames + " frames";
            this.historyLoaded = true;
            this.updateStatus();
         }
      }

      private function loadHistory() : void
      {
         var stored:* = undefined;
         var parsed:Object = null;
         try
         {
            stored = this.codeObj.modStorage.load(HISTORY_STORE);
            if(stored === false)
            {
               this.diag.historyLoad = "no file yet";
            }
            else
            {
               parsed = this.parseJson(String(stored)) as Object;
               if(parsed != null && parsed.items != null)
               {
                  this.mergeLoaded(parsed.items);
                  this.diag.historyLoad = "ok, " + this.pruneHistory() + " entries older than " + HISTORY_KEEP_DAYS + " days dropped";
               }
               else
               {
                  this.diag.historyLoad = "file has no items object";
                  this.historySaveBlocked = true;
               }
            }
         }
         catch(error:Error)
         {
            this.diag.historyLoad = "error: " + error.message;
            this.historySaveBlocked = true;
         }
         // A file that exists but cannot be read is never overwritten: saving would replace
         // all its history with this session's prices.
         if(this.historySaveBlocked)
         {
            this.addError(HISTORY_STORE + ".json could not be read, so it will not be saved this session");
         }
         this.historyLoaded = true;
         this.loadFeedRecord();
         this.feedPending = true;
      }

      // Drops entries older than HISTORY_KEEP_DAYS (suggestions only use SUGGEST_DAYS), and
      // items left with none, so the file stops growing. Returns how many were dropped.
      private function pruneHistory() : int
      {
         var cutoff:Number = nowSeconds() - HISTORY_KEEP_DAYS * DAY_SECONDS;
         var keys:Array = [];
         var key:String = null;
         var kept:Array = null;
         var entry:Array = null;
         var dropped:int = 0;
         for(key in this.history)
         {
            keys.push(key);
         }
         for each(key in keys)
         {
            kept = [];
            for each(entry in this.history[key])
            {
               if(Number(entry[0]) >= cutoff)
               {
                  kept.push(entry);
               }
            }
            dropped += (this.history[key] as Array).length - kept.length;
            if(kept.length == 0)
            {
               delete this.history[key];
            }
            else
            {
               this.history[key] = kept;
            }
         }
         if(dropped > 0)
         {
            this.historyDirty = true;
            this.historyVersion++;
         }
         return dropped;
      }

      // ---- Better Containers feed -------------------------------------------------------

      private function loadFeedRecord() : void
      {
         var stored:* = undefined;
         var parsed:Object = null;
         try
         {
            stored = this.codeObj.modStorage.load(FEED_STORE);
            if(stored !== false)
            {
               parsed = this.parseJson(String(stored)) as Object;
               if(parsed != null)
               {
                  if(parsed.written != null)
                  {
                     this.feedWritten = parsed.written;
                  }
                  if(parsed.originals != null)
                  {
                     this.feedOriginals = parsed.originals;
                  }
                  // ownedValues: key -> item value. (Older records kept keys only, as
                  // "owned"; those are dropped and rebuilt at your machine.)
                  if(parsed.ownedValues != null)
                  {
                     this.ownedValues = parsed.ownedValues;
                  }
                  this.marketMode = parsed.marketMode == true;
               }
            }
         }
         catch(error:Error)
         {
            this.addError("feed record: " + error.message);
         }
      }

      private function saveFeedRecord() : void
      {
         this.codeObj.modStorage.save(FEED_STORE,"{\"version\":2,\"marketMode\":" + (this.marketMode ? "true" : "false") + ",\"written\":" + encode(this.feedWritten) + ",\"originals\":" + encode(this.feedOriginals) + ",\"ownedValues\":" + encode(this.ownedValues) + "}");
      }

      // Market value of an item key, as the panel shows it, or NaN when no vendor had it.
      // Legendary items use every level with the same name and stars.
      private function marketPrice(key:String) : Number
      {
         var stars:int = starsOf(key);
         var entries:Array = stars > 0 ? this.legendaryEntries(key.substr(0,key.indexOf("|")),stars) : this.history[key] as Array;
         var stats:Object = this.suggest(entries,null,this.ownedValue(key));
         return int(stats.count) >= MARKET_MIN_VENDORS ? Number(stats.sell) : NaN;
      }

      // The highlighted item's value, from its list entry or failing that your machine.
      private function panelItemValue(entry:Object, key:String) : Number
      {
         if(entry != null && entry.itemValue != null && Number(entry.itemValue) > 0)
         {
            return Number(entry.itemValue);
         }
         return this.ownedValue(key);
      }

      // The item value of an item seen at your machine, or NaN.
      private function ownedValue(key:String) : Number
      {
         return this.ownedValues[key] !== undefined && this.ownedValues[key] !== null ? Number(this.ownedValues[key]) : NaN;
      }

      // Writes PriceScout's prices into Better Containers' remembered prices, which its
      // Vendor manager reads on the first M press of a machine visit.
      //   Normal mode: adds the market price for non-legendary items seen at
      //   FEED_MIN_VENDORS+ vendors, only where you have no price of your own.
      //   Market-price mode: every remembered price and every item you own is set to the
      //   market price, or 0 when no vendor had it. Your own prices are kept in
      //   feedOriginals and put back when the mode is switched off.
      private function feedBetterContainers() : void
      {
         var stored:* = undefined;
         var doc:Object = null;
         var counts:Object = null;
         try
         {
            stored = this.codeObj.modStorage.load(BC_STORE);
            doc = stored === false ? {"version":1,"prices":{}} : this.parseJson(String(stored)) as Object;
            if(doc == null || doc.prices == null || doc.prices is Array || typeof doc.prices != "object")
            {
               this.diag.feed = "not fed: " + BC_STORE + ".json has no prices object";
               return;
            }
            counts = this.marketMode ? this.feedMarketMode(doc.prices) : this.feedNormal(doc.prices);
            if(int(counts.changed) > 0 && this.codeObj.modStorage.save(BC_STORE,encode(doc)) != true)
            {
               this.addError("modStorage.save(" + BC_STORE + ") returned false");
               return;
            }
            this.saveFeedRecord();
            this.feedStale = false;
            this.bcPrices = doc.prices;
            this.bcPricesAt = getTimer();
            counts.at = nowSeconds();
            counts.mode = this.marketMode ? "market-price" : "normal";
            this.diag.feed = counts;
            this.logEvent("fed Better Containers (" + counts.mode + "): " + encode(counts));
         }
         catch(error:Error)
         {
            this.addError("feed: " + error.message);
         }
      }

      private function feedNormal(prices:Object) : Object
      {
         var key:String = null;
         var keys:Array = [];
         var price:int = 0;
         var current:* = undefined;
         var counts:Object = {
            "changed":0,
            "added":0,
            "updated":0,
            "yoursKept":0,
            "restored":0,
            "removed":0
         };
         // Undo market-price mode: your prices back, its other values removed, as long as
         // they still hold what PriceScout wrote.
         for(key in this.feedOriginals)
         {
            keys.push(key);
         }
         for each(key in keys)
         {
            if(this.isOurs(key,prices[key]))
            {
               prices[key] = this.feedOriginals[key];
               counts.restored++;
               counts.changed++;
            }
            delete this.feedWritten[key];
         }
         this.feedOriginals = {};
         keys = [];
         for(key in this.feedWritten)
         {
            keys.push(key);
         }
         for each(key in keys)
         {
            if(this.normalFeedPrice(key) < 0)
            {
               if(Number(this.feedWritten[key]) != REMOVED && this.isOurs(key,prices[key]))
               {
                  delete prices[key];
                  counts.removed++;
                  counts.changed++;
               }
               delete this.feedWritten[key];
            }
         }
         for(key in this.history)
         {
            price = this.normalFeedPrice(key);
            if(price < 0)
            {
               continue;
            }
            current = prices[key];
            if(current === undefined || current === null)
            {
               prices[key] = price;
               this.feedWritten[key] = price;
               counts.added++;
               counts.changed++;
            }
            else if(this.feedWritten[key] !== undefined && Number(current) == Number(this.feedWritten[key]))
            {
               if(Number(current) != price)
               {
                  prices[key] = price;
                  counts.updated++;
                  counts.changed++;
               }
               this.feedWritten[key] = price;
            }
            else
            {
               // A price you set in Better Containers: never touched in normal mode.
               delete this.feedWritten[key];
               counts.yoursKept++;
            }
         }
         return counts;
      }

      // The normal feed's price for a key, or -1 when it does not feed that key.
      private function normalFeedPrice(key:String) : int
      {
         var stats:Object = null;
         if(starsOf(key) > 0 || !(this.history[key] is Array))
         {
            return -1;
         }
         stats = this.suggest(this.history[key] as Array,null,this.ownedValue(key));
         if(int(stats.count) < FEED_MIN_VENDORS)
         {
            return -1;
         }
         return int(Math.max(1,Math.min(BC_MAX_PRICE,Math.round(Number(stats.sell)))));
      }

      private function feedMarketMode(prices:Object) : Object
      {
         var keys:Object = {};
         var key:String = null;
         var market:Number = NaN;
         var price:int = 0;
         var current:* = undefined;
         var ours:Boolean = false;
         var counts:Object = {
            "changed":0,
            "atMarket":0,
            "atItemValue":0,
            "removed":0,
            "yoursReplaced":0
         };
         for(key in prices)
         {
            keys[key] = true;
         }
         for(key in this.ownedValues)
         {
            keys[key] = true;
         }
         for(key in keys)
         {
            market = this.marketPrice(key);
            // No market price: the item value (known for items seen at your machine), or
            // no remembered price at all (REMOVED), so Better Containers uses the item
            // value itself. Never 0: "Sell checked" would list those items for free.
            if(!isNaN(market))
            {
               price = int(Math.max(1,Math.min(BC_MAX_PRICE,Math.round(market))));
            }
            else if(this.ownedValues[key] !== undefined && Number(this.ownedValues[key]) > 0)
            {
               price = this.noMarketPrice(Number(this.ownedValues[key]));
            }
            else
            {
               price = REMOVED;
            }
            current = prices[key];
            ours = this.isOurs(key,current);
            if(current !== undefined && current !== null && !ours)
            {
               // Your price: kept to put back when the mode is switched off.
               if(this.feedOriginals[key] === undefined)
               {
                  this.feedOriginals[key] = current;
               }
               counts.yoursReplaced++;
            }
            if(price == REMOVED)
            {
               if(current !== undefined && current !== null)
               {
                  delete prices[key];
                  counts.changed++;
               }
               counts.removed++;
            }
            else
            {
               if(current === undefined || current === null || Number(current) != price)
               {
                  prices[key] = price;
                  counts.changed++;
               }
               if(isNaN(market))
               {
                  counts.atItemValue++;
               }
               else
               {
                  counts.atMarket++;
               }
            }
            this.feedWritten[key] = price;
         }
         return counts;
      }

      // Item value plus the no-market markup, rounded, at least 1.
      private function noMarketPrice(itemValue:Number) : int
      {
         return int(Math.max(1,Math.min(BC_MAX_PRICE,Math.round(itemValue * (1 + this.noMarketMarkup / 100)))));
      }

      private function markupText() : String
      {
         return this.noMarketMarkup > 0 ? "item value +" + this.noMarketMarkup + "%" : "item value";
      }

      // True when Better Containers' value for key is what PriceScout last wrote (or
      // removed), so it is PriceScout's to change.
      private function isOurs(key:String, current:*) : Boolean
      {
         if(this.feedWritten[key] === undefined)
         {
            return false;
         }
         if(Number(this.feedWritten[key]) == REMOVED)
         {
            return current === undefined || current === null;
         }
         return current !== undefined && current !== null && Number(current) == Number(this.feedWritten[key]);
      }

      // Every item you have at your own machine (carried and in the machine's stash list),
      // so market-price mode can price items Better Containers has no price for.
      private function captureOwned() : void
      {
         var sources:Array = [this.inventoryData,this.playerData];
         var source:Object = null;
         var entry:Object = null;
         var key:String = null;
         var added:int = 0;
         if(this.typeData == null || this.typeData.ownsVendor != true || uint(this.typeData.menuType) != MODE_VENDING_MACHINE)
         {
            return;
         }
         for each(source in sources)
         {
            if(source == null || !(source.InventoryList is Array))
            {
               continue;
            }
            if(source == this.inventoryData)
            {
               this.ownedStashSeen = true;
            }
            for each(entry in source.InventoryList)
            {
               if(entry == null || entry.isCurrency == true || entry.isQuestItem == true)
               {
                  continue;
               }
               key = itemKey(entry);
               if(this.ownedValues[key] === undefined || Number(this.ownedValues[key]) != Number(entry.itemValue))
               {
                  this.ownedValues[key] = Number(entry.itemValue);
                  added++;
               }
            }
         }
         if(added > 0)
         {
            this.feedStale = true;
            this.visitApplied = false;
         }
      }

      // At your own machine: F10 switches market-price mode; M (Better Containers'
      // Vendor manager) is watched so the panel can say whether a reopen is needed.
      // In market-price mode the prices are written as soon as your item lists arrive,
      // before the Vendor manager reads them on the first M press.
      private function pollKeys(e:Event) : void
      {
         var atOwn:Boolean = false;
         var modeDown:Boolean = false;
         var managerDown:Boolean = false;
         if(this.codeObj == null)
         {
            return;
         }
         try
         {
            if(!this.keysRegistered)
            {
               this.keysRegistered = this.codeObj.call("Input.RegisterKey",MODE_KEY) == true && this.codeObj.call("Input.RegisterKey",MANAGER_KEY) == true;
               this.diag.hotkey = this.keysRegistered ? "F10 and M registered" : "Input.RegisterKey failed";
               if(!this.keysRegistered)
               {
                  removeEventListener(Event.ENTER_FRAME,this.pollKeys);
                  return;
               }
            }
            atOwn = this.menuOpen() && this.typeData != null && this.typeData.ownsVendor == true && uint(this.typeData.menuType) == MODE_VENDING_MACHINE;
            if(!atOwn)
            {
               this.modeKeyDown = false;
               return;
            }
            modeDown = this.codeObj.call("Input.IsKeyPressed",MODE_KEY) == true;
            managerDown = this.codeObj.call("Input.IsKeyPressed",MANAGER_KEY) == true;
            if(managerDown && !this.managerKeyDown)
            {
               this.managerOpenedThisVisit = true;
            }
            this.managerKeyDown = managerDown;
            if(modeDown && !this.modeKeyDown)
            {
               this.marketMode = !this.marketMode;
               this.logEvent("market-price mode " + (this.marketMode ? "on" : "off"));
               this.feedBetterContainers();
               this.visitApplied = true;
               this.appliedAfterManager = this.managerOpenedThisVisit;
               this.refreshPanel();
            }
            this.modeKeyDown = modeDown;
            if(this.marketMode && !this.visitApplied && (this.ownedStashSeen || getTimer() - this.visitStartedAt > MARKET_APPLY_WAIT_MS))
            {
               this.feedBetterContainers();
               this.visitApplied = true;
               this.appliedAfterManager = this.managerOpenedThisVisit;
               this.refreshPanel();
            }
         }
         catch(error:Error)
         {
            this.addError("keys: " + error.message);
            removeEventListener(Event.ENTER_FRAME,this.pollKeys);
         }
      }

      private static function starsOf(key:String) : int
      {
         return int(key.substr(key.lastIndexOf("|") + 1));
      }

      // Entries recorded before the file loaded go after the stored ones.
      private function mergeLoaded(items:Object) : void
      {
         var key:String = null;
         var merged:Object = {};
         for(key in items)
         {
            if(items[key] is Array)
            {
               merged[key] = (items[key] as Array).concat();
            }
         }
         for(key in this.history)
         {
            merged[key] = merged[key] is Array ? (merged[key] as Array).concat(this.history[key]) : this.history[key];
         }
         this.history = merged;
         this.historyVersion++;
      }

      private function onSaveTimer(e:TimerEvent) : void
      {
         if(this.codeObj == null)
         {
            return;
         }
         try
         {
            if(this.historyDirty && this.historyLoaded && !this.historySaveBlocked)
            {
               this.historyDirty = false;
               if(this.codeObj.modStorage.save(HISTORY_STORE,this.encodeHistory()) != true)
               {
                  this.addError("modStorage.save(" + HISTORY_STORE + ") returned false");
               }
            }
            if(this.feedPending && this.historyLoaded && !this.menuOpen())
            {
               this.feedPending = false;
               this.feedBetterContainers();
            }
            // Full diagnostics: everything, whenever it changes. Otherwise a short summary
            // with no vendor names, written at login and when an error is added.
            if(this.diagDirty && (this.fullDiagnostics || this.diagMustSave))
            {
               this.diagDirty = false;
               this.diagMustSave = false;
               this.diag.savedAt = nowSeconds();
               if(this.codeObj.modStorage.save(DIAG_STORE,encode(this.fullDiagnostics ? this.diag : this.diagSummary())) != true)
               {
                  this.addError("modStorage.save(" + DIAG_STORE + ") returned false");
               }
            }
         }
         catch(error:Error)
         {
            this.addError("save: " + error.message);
         }
      }

      private function encodeHistory() : String
      {
         return "{\"version\":1,\"build\":" + quote(BUILD) + ",\"fields\":[\"time\",\"price\",\"count\",\"vendor\",\"menuType\"],\"items\":" + encode(this.history) + "}";
      }

      // ---- Data providers -----------------------------------------------------------

      private function subscribe(provider:String) : void
      {
         var initial:Object = null;
         this.diag.events[provider] = 0;
         try
         {
            this.dataManager.Subscribe(provider,this.handlerFor(provider));
            this.diag.subscribe[provider] = "ok";
         }
         catch(error:Error)
         {
            this.diag.subscribe[provider] = "error: " + error.message;
            this.addError("Subscribe(" + provider + "): " + error.message);
            return;
         }
         try
         {
            initial = this.dataManager.GetDataFromClient(provider);
            if(initial != null && initial.data != null)
            {
               this.onProvider(provider,initial.data,true);
            }
         }
         catch(error:Error)
         {
            this.addError("GetDataFromClient(" + provider + "): " + error.message);
         }
      }

      private function handlerFor(provider:String) : Function
      {
         var self:PriceScout = this;
         return function(event:*):void
         {
            self.onProvider(provider,event != null ? event.data : null,false);
         };
      }

      public function onProvider(provider:String, data:Object, initial:Boolean) : void
      {
         try
         {
            if(!initial)
            {
               this.diag.events[provider] = int(this.diag.events[provider]) + 1;
            }
            if(provider == TYPE_PROVIDER)
            {
               this.typeData = data;
               this.diag.lastType = dump(data,2);
               this.diag.lastTypeAt = nowSeconds();
               this.onTypeData();
               this.processVendor();
            }
            else if(provider == INVENTORY_PROVIDER)
            {
               this.inventoryData = data;
               this.diag.lastInventory = this.describeInventory(data);
               this.logEvent((initial ? "read " : "event ") + provider + ": " + listSummary(data));
               // At your own machine this list holds its stash; it arrives like the shop
               // list does, as an update without a list that needs reading again.
               if(!initial && (data == null || !(data.InventoryList is Array)) && this.typeData != null && this.typeData.ownsVendor == true)
               {
                  this.rewatch(INVENTORY_PROVIDER,"update without a list");
               }
               this.processVendor();
            }
            else if(provider == OFFERS_PROVIDER)
            {
               this.offersData = data;
               this.diag.lastOffers = this.describeInventory(data);
               this.logEvent((initial ? "read " : "event ") + provider + ": " + listSummary(data));
               // After a vendor opens, the game signals this provider about 2 s later
               // without the list; reading it again then returns the full list.
               if(!initial && (data == null || !(data.InventoryList is Array)))
               {
                  this.rewatch(OFFERS_PROVIDER,"update without a list");
               }
               this.processVendor();
            }
            else if(provider == HUD_MODE_PROVIDER)
            {
               this.onHudMode(data != null ? String(data.hudMode) : null);
               return;
            }
            else if(provider == CONTROL_PROVIDER)
            {
               this.playerData = data;
            }
            else if(provider == CARD_PROVIDER)
            {
               this.cardHandle = data != null ? Number(data.serverHandleID) : 0;
               this.cardText = data != null && data.text != null ? String(data.text) : null;
               this.cardData = data;
               this.diag.lastCard = {
                  "at":nowSeconds(),
                  "serverHandleID":this.cardHandle,
                  "fields":dump(data,0)
               };
            }
            if(provider == TYPE_PROVIDER || provider == INVENTORY_PROVIDER || provider == CONTROL_PROVIDER)
            {
               this.captureOwned();
            }
            this.refreshPanel();
            this.diagDirty = true;
            this.updateStatus();
         }
         catch(error:Error)
         {
            this.addError(provider + " handler: " + error.message);
         }
      }

      // A new vendor (or the same one opened again) gets fresh item lists. The HUD's watch
      // on CampVendingOfferData otherwise keeps the first list it received in the session.
      private function onTypeData() : void
      {
         var vendor:String = this.typeData != null ? this.currentVendor() : null;
         this.logEvent("type menuType=" + (this.typeData != null ? this.typeData.menuType : "-") + " owns=" + (this.typeData != null ? this.typeData.ownsVendor : "-") + " vendor=" + vendor);
         if(vendor == null || vendor == this.lastVendor)
         {
            return;
         }
         this.lastVendor = vendor;
         this.visitStartedAt = getTimer();
         this.rewatch(OFFERS_PROVIDER,"vendor opened");
         this.rewatch(INVENTORY_PROVIDER,"vendor opened");
      }

      // Drops the HUD's watch on a provider and watches it again, then reads the result.
      private function rewatch(provider:String, reason:String) : void
      {
         var now:int = getTimer();
         var fresh:Object = null;
         var data:Object = null;
         if(this.rewatching || this.dataManager == null)
         {
            return;
         }
         if(this.lastRewatch[provider] != null && now - int(this.lastRewatch[provider]) < REWATCH_MIN_MS)
         {
            return;
         }
         this.lastRewatch[provider] = now;
         this.rewatching = true;
         try
         {
            this.dataManager.RemoveWatchFromDataConnector(provider);
            this.dataManager.Subscribe(provider,this.handlerFor(provider));
            fresh = this.dataManager.GetDataFromClient(provider);
            data = fresh != null ? fresh.data : null;
            this.diag.rewatches = int(this.diag.rewatches) + 1;
            this.logEvent("rewatch " + provider + " (" + reason + ")");
            if(data != null)
            {
               this.onProvider(provider,data,true);
            }
         }
         catch(error:Error)
         {
            this.addError("rewatch " + provider + ": " + error.message);
         }
         this.rewatching = false;
      }

      // Menu closed: forget its data so the next menu cannot reuse it.
      private function onMenuClosed() : void
      {
         if(this.feedStale)
         {
            this.feedPending = true;
         }
         this.typeData = null;
         this.offersData = null;
         this.inventoryData = null;
         this.cardHandle = 0;
         this.cardText = null;
         this.lastVendor = null;
         this.managerOpenedThisVisit = false;
         this.managerKeyDown = false;
         this.visitApplied = false;
         this.appliedAfterManager = false;
         this.ownedStashSeen = false;
      }

      private function logEvent(text:String) : void
      {
         var log:Array = this.diag.eventLog as Array;
         var time:Date = null;
         if(!this.fullDiagnostics)
         {
            return;
         }
         time = new Date();
         log.push(pad2(time.hours) + ":" + pad2(time.minutes) + ":" + pad2(time.seconds) + " " + text);
         if(log.length > MAX_LOG)
         {
            log.shift();
         }
         this.diagDirty = true;
      }

      private static function pad2(value:int) : String
      {
         return value < 10 ? "0" + value : String(value);
      }

      private static function listSummary(data:Object) : String
      {
         var list:Array = data != null ? data.InventoryList as Array : null;
         if(list == null)
         {
            return "no list";
         }
         return list.length + " items, fingerprint " + fingerprint(list) + (list.length > 0 ? ", first \"" + String(list[0].text) + "\"" : "");
      }

      // Identifies a list by its items' serverHandleIDs.
      private static function fingerprint(list:Array) : String
      {
         var handles:Array = [];
         var entry:Object = null;
         for each(entry in list)
         {
            handles.push(entry != null ? String(entry.serverHandleID) : "");
         }
         handles.sort();
         return hashText(handles.join(","));
      }

      private function describeInventory(data:Object) : Object
      {
         var list:Array = data != null ? data.InventoryList as Array : null;
         var sample:Array = [];
         var i:int = 0;
         while(list != null && i < list.length && i < 3)
         {
            sample.push(dump(list[i],2));
            i++;
         }
         return {
            "at":nowSeconds(),
            "count":list != null ? list.length : -1,
            "topLevelFields":dump(data,0),
            "sampleItems":sample
         };
      }

      private function processVendor() : void
      {
         var list:Array = null;
         var mode:uint = 0;
         var vendor:String = null;
         var entry:Object = null;
         var price:Number = NaN;
         var recordedNow:int = 0;
         var source:Object = null;
         var print:String = null;
         var owner:String = null;
         if(this.typeData == null)
         {
            return;
         }
         mode = uint(this.typeData.menuType);
         source = mode == MODE_VENDING_MACHINE ? this.offersData : this.inventoryData;
         list = source != null ? source.InventoryList as Array : null;
         if(list == null)
         {
            return;
         }
         // A list already seen at a different vendor is stale data, never this vendor's.
         if(list.length > 0)
         {
            print = fingerprint(list);
            owner = this.typeData.ownsVendor == true ? "own" : this.currentVendor();
            if(this.listOwners[print] != null && this.listOwners[print] != owner)
            {
               this.skip("stale list from another vendor");
               this.logEvent("refused list " + print + ": belongs to " + this.listOwners[print] + ", open vendor is " + owner);
               this.rewatch(source == this.offersData ? OFFERS_PROVIDER : INVENTORY_PROVIDER,"stale list");
               return;
            }
            this.listOwners[print] = owner;
         }
         if(this.typeData.ownsVendor == true)
         {
            this.skip("own vendor or container");
            return;
         }
         if(mode == MODE_NPCVENDING)
         {
            this.skip("npc vendor");
            return;
         }
         vendor = this.currentVendor();
         for each(entry in list)
         {
            price = this.priceOf(entry,mode);
            if(isNaN(price))
            {
               continue;
            }
            if(this.record(itemKey(entry),price,int(entry.count),vendor,mode))
            {
               recordedNow++;
            }
         }
         if(recordedNow == 0 && list.length > 0)
         {
            this.skip("nothing new: no priced items or already recorded today (menuType " + mode + ")");
         }
      }

      // Asking price of an item in another player's vending machine, or NaN.
      private function priceOf(entry:Object, mode:uint) : Number
      {
         var vending:Object = entry != null ? entry.vendingData : null;
         if(vending != null && uint(vending.machineType) == MACHINE_TYPE_VENDING && vending.price != null)
         {
            return Number(vending.price);
         }
         if(mode == MODE_PLAYERVENDING && entry != null && entry.isOffered == true && entry.offerValue != null)
         {
            return Number(entry.offerValue);
         }
         return NaN;
      }

      // One entry per item, vendor, price and day.
      private function record(key:String, price:Number, count:int, vendor:String, mode:uint) : Boolean
      {
         var now:Number = nowSeconds();
         var day:Number = Math.floor(now / DAY_SECONDS);
         var list:Array = this.history[key] as Array;
         var old:Array = null;
         if(list == null)
         {
            list = [];
            this.history[key] = list;
         }
         for each(old in list)
         {
            if(old[3] == vendor && Number(old[1]) == price && Math.floor(Number(old[0]) / DAY_SECONDS) == day)
            {
               return false;
            }
         }
         list.push([now,price,count,vendor,mode]);
         if(list.length > MAX_PER_ITEM)
         {
            list.splice(0,list.length - MAX_PER_ITEM);
         }
         this.diag.recorded = int(this.diag.recorded) + 1;
         (this.diag.lastRecorded as Array).push(key + " = " + price);
         if((this.diag.lastRecorded as Array).length > 10)
         {
            (this.diag.lastRecorded as Array).shift();
         }
         this.historyDirty = true;
         this.feedStale = true;
         this.historyVersion++;
         return true;
      }

      private function skip(reason:String) : void
      {
         this.diag.skipped[reason] = int(this.diag.skipped[reason]) + 1;
      }

      // The open vendor, as stored in the history: a hash of its header (the owner's name).
      private function currentVendor() : String
      {
         return hashText(String(this.typeData.defaultHeaderText) + "|" + String(this.typeData.menuSubType));
      }

      // ---- Suggestions ----------------------------------------------------------------

      // Prices from each vendor's lowest price on the latest day it was seen, over the last
      // SUGGEST_DAYS days. Free listings, placeholder prices and excludeVendor are left out.
      //   sell     the selling price, by sellMethod, blended with itemValue (+markup) when
      //            itemValueWeight is set and itemValue is known
      //   market   the lower quartile, what deals are measured against
      //   median, low, high, count
      private function suggest(entries:Array, excludeVendor:String, itemValue:Number = 0) : Object
      {
         var cutoff:Number = nowSeconds() - SUGGEST_DAYS * DAY_SECONDS;
         var best:Object = {};
         var prices:Array = [];
         var entry:Array = null;
         var vendor:String = null;
         var price:Number = NaN;
         var day:Number = NaN;
         var sell:Number = NaN;
         var blended:Boolean = false;
         for each(entry in entries)
         {
            vendor = String(entry[3]);
            price = Number(entry[1]);
            if(Number(entry[0]) < cutoff || price <= 0 || price >= PLACEHOLDER_PRICE || vendor == excludeVendor)
            {
               continue;
            }
            day = Math.floor(Number(entry[0]) / DAY_SECONDS);
            if(best[vendor] == null || day > best[vendor].day || (day == best[vendor].day && price < best[vendor].price))
            {
               best[vendor] = {"day":day,"price":price};
            }
         }
         for(vendor in best)
         {
            prices.push(best[vendor].price);
         }
         if(prices.length == 0)
         {
            return {"count":0};
         }
         prices.sort(Array.NUMERIC);
         sell = this.methodPrice(prices);
         if(this.itemValueWeight > 0 && itemValue > 0)
         {
            // Shrinks thin markets toward the item value: with 2 vendors and a weight of 3
            // the item value counts for 60%, with 30 vendors for 9%.
            sell = (prices.length * sell + this.itemValueWeight * itemValue * (1 + this.noMarketMarkup / 100)) / (prices.length + this.itemValueWeight);
            blended = true;
         }
         return {
            "count":prices.length,
            "sell":Math.max(1,Math.round(sell)),
            "blended":blended,
            "market":Math.round(quantile(prices,MARKET_QUANTILE)),
            "median":Math.round(quantile(prices,0.5)),
            "low":prices[0],
            "high":prices[prices.length - 1]
         };
      }

      // The selling price of sorted vendor prices by sellMethod, before blending.
      private function methodPrice(sorted:Array) : Number
      {
         var q1:Number = NaN;
         var q3:Number = NaN;
         var fence:Number = NaN;
         var kept:Array = null;
         var price:Number = NaN;
         if(this.sellMethod == METHOD_UNDERCUT)
         {
            return Number(sorted[0]) * (1 - this.undercutPercent / 100);
         }
         if(this.sellMethod == METHOD_FENCED_MEDIAN)
         {
            // Tukey's fences: prices more than 1.5 interquartile ranges outside the middle
            // half are left out. With 3 vendors or fewer, nothing is ever outside them.
            q1 = quantile(sorted,0.25);
            q3 = quantile(sorted,0.75);
            fence = TUKEY_K * (q3 - q1);
            kept = [];
            for each(price in sorted)
            {
               if(price >= q1 - fence && price <= q3 + fence)
               {
                  kept.push(price);
               }
            }
            return quantile(kept,0.5);
         }
         return quantile(sorted,this.sellPercentile / 100);
      }

      // The active selling method, for the panel and diagnostics.
      private function methodText() : String
      {
         if(this.sellMethod == METHOD_UNDERCUT)
         {
            return "cheapest -" + this.undercutPercent + "%";
         }
         if(this.sellMethod == METHOD_FENCED_MEDIAN)
         {
            return "fenced median";
         }
         return "percentile " + this.sellPercentile;
      }

      // True when the panel should name the method: anything but the default lower quartile.
      private function methodIsCustom() : Boolean
      {
         return this.sellMethod != METHOD_PERCENTILE || this.sellPercentile != DEFAULT_SELL_PERCENTILE;
      }

      // The list entry with this serverHandleID, or failing that this name, in the lists
      // the mod has for the open menu.
      private function findEntry(handle:Number, name:String) : Object
      {
         var sources:Array = [this.offersData,this.inventoryData,this.playerData];
         var source:Object = null;
         var entry:Object = null;
         var byName:Object = null;
         var wanted:String = name != null ? plainName(name) : null;
         for each(source in sources)
         {
            if(source == null || !(source.InventoryList is Array))
            {
               continue;
            }
            for each(entry in source.InventoryList)
            {
               if(entry == null)
               {
                  continue;
               }
               if(Number(entry.serverHandleID) == handle)
               {
                  return entry;
               }
               if(byName == null && wanted != null && plainName(String(entry.text)) == wanted)
               {
                  byName = entry;
               }
            }
         }
         return byName;
      }

      // History entries for a legendary item: same name and star count, any level.
      private function legendaryEntries(name:String, stars:int) : Array
      {
         var wanted:String = plainName(name);
         var out:Array = [];
         var key:String = null;
         for(key in this.history)
         {
            if(starsOf(key) == stars && plainName(key.substr(0,key.indexOf("|"))) == wanted)
            {
               out = out.concat(this.history[key]);
            }
         }
         return out;
      }

      // Saves the highlighted legendary item's list entry and item card to the diag file
      // (up to MAX_LEGENDARY_SAMPLES items), to see how effects are reported.
      private function captureLegendaryCard(entry:Object) : void
      {
         var samples:Array = this.diag.legendaryCards as Array;
         var sample:Object = null;
         if(!this.fullDiagnostics)
         {
            return;
         }
         var rows:Array = [];
         var row:Object = null;
         if(samples == null)
         {
            samples = [];
            this.diag.legendaryCards = samples;
         }
         for each(sample in samples)
         {
            if(sample.serverHandleID == this.cardHandle)
            {
               return;
            }
         }
         if(samples.length >= MAX_LEGENDARY_SAMPLES || this.cardData == null || Number(this.cardData.serverHandleID) != this.cardHandle)
         {
            return;
         }
         for each(row in this.cardData.itemCardEntries)
         {
            rows.push(dump(row,1));
         }
         samples.push({
            "serverHandleID":this.cardHandle,
            "listEntry":dump(entry,1),
            "cardText":dump(this.cardData.text,0),
            "cardEntries":rows
         });
         this.logEvent("captured legendary card: " + String(entry.text));
      }

      // Every history entry whose item name matches, across levels and star counts.
      private function entriesByName(name:String) : Array
      {
         var wanted:String = plainName(name);
         var out:Array = [];
         var key:String = null;
         for(key in this.history)
         {
            if(plainName(key.substr(0,key.indexOf("|"))) == wanted)
            {
               out = out.concat(this.history[key]);
            }
         }
         return out;
      }

      // Lower case, without the leading space and sort-tag glyph (U+00B6) some item
      // sorting setups put in front of names.
      private static function plainName(text:String) : String
      {
         var out:String = text.toLowerCase();
         while(out.length > 0 && (out.charAt(0) == " " || out.charCodeAt(0) == 182))
         {
            out = out.substr(1);
         }
         return out;
      }

      private function menuOpen() : Boolean
      {
         return this.hudMode != null && STATUS_HUD_MODES.indexOf(this.hudMode) < 0;
      }

      // Item name without the sort-tag glyph and [TAG] prefix, at most maxLength characters.
      private static function shortName(text:String, maxLength:int) : String
      {
         var name:String = text;
         while(name.length > 0 && (name.charAt(0) == " " || name.charCodeAt(0) == 182 || name.charCodeAt(0) == 177))
         {
            name = name.substr(1);
         }
         if(name.charAt(0) == "[" && name.indexOf("] ") > 0)
         {
            name = name.substr(name.indexOf("] ") + 2);
         }
         return name.length > maxLength ? name.substr(0,maxLength - 1) + "..." : name;
      }

      // Better Containers' remembered prices, re-read each time your own machine opens.
      private function loadBcPrices() : void
      {
         var stored:* = undefined;
         var doc:Object = null;
         if(this.codeObj == null)
         {
            return;
         }
         try
         {
            stored = this.codeObj.modStorage.load(BC_STORE);
            if(stored === false)
            {
               this.bcPrices = {};
               this.bcText = null;
               return;
            }
            // Parsing is the slow part; skip it when the file has not changed.
            if(this.bcPrices != null && String(stored) == this.bcText)
            {
               return;
            }
            doc = this.parseJson(String(stored)) as Object;
            this.bcPrices = doc != null && doc.prices != null ? doc.prices : null;
            this.bcText = String(stored);
         }
         catch(error:Error)
         {
            this.addError("read " + BC_STORE + ": " + error.message);
         }
      }

      // Linear-interpolated quantile (0..1) of sorted numbers.
      private static function quantile(sorted:Array, q:Number) : Number
      {
         var pos:Number = q * (sorted.length - 1);
         var below:int = int(Math.floor(pos));
         var above:int = int(Math.min(sorted.length - 1,below + 1));
         return Number(sorted[below]) + (Number(sorted[above]) - Number(sorted[below])) * (pos - below);
      }

      private static function percentDiff(value:Number, reference:Number) : String
      {
         var pct:Number = Math.round((value - reference) / reference * 100);
         if(pct == 0)
         {
            return "at market";
         }
         return (pct > 0 ? "+" : "") + pct + "%";
      }

      // Same key Better Containers uses for its remembered sale prices.
      private static function itemKey(entry:Object) : String
      {
         return String(entry.text).toLowerCase() + "|" + int(entry.itemLevel) + "|" + (entry.isLegendary == true ? int(entry.numLegendaryStars) : 0);
      }

      // ---- Price panel ------------------------------------------------------------------
      //
      // Lines of styled pieces ({t:text, s:style}) laid out left to right, below the vendor
      // menu's button bar. Styles follow Better Containers' palette.

      private static function piece(text:String, style:String) : Object
      {
         return {"t":text,"s":style};
      }

      // Green when the price is good for you, red when it is not. buying: lower is good.
      private static function percentPiece(value:Number, reference:Number, buying:Boolean) : Object
      {
         var style:String = "dim";
         if(value < reference)
         {
            style = buying ? "good" : "bad";
         }
         else if(value > reference)
         {
            style = buying ? "bad" : "good";
         }
         return piece(percentDiff(value,reference),style);
      }

      private static function linesText(lines:Array) : String
      {
         var out:Array = [];
         var line:Array = null;
         var parts:Array = null;
         var p:Object = null;
         for each(line in lines)
         {
            parts = [];
            for each(p in line)
            {
               parts.push(p.t);
            }
            out.push(parts.join(" "));
         }
         return out.join("\n");
      }

      // While a vending machine is open: the highlighted item, and either the best deals
      // (another player's shop) or market-price mode (your own machine).
      private function refreshPanel() : void
      {
         var lines:Array = [];
         var item:Array = null;
         var list:Array = null;
         if(this.panelBox == null)
         {
            return;
         }
         if(!this.menuOpen() || this.typeData == null || uint(this.typeData.menuType) != MODE_VENDING_MACHINE)
         {
            this.showPanel(null);
            return;
         }
         if(this.cardHandle != 0)
         {
            item = this.highlightedPieces();
            if(item != null)
            {
               lines.push(item);
            }
         }
         list = this.offersData != null ? this.offersData.InventoryList as Array : null;
         if(this.typeData.ownsVendor != true && list != null && list.length > 0)
         {
            lines.push(this.dealsPieces(list));
         }
         if(this.typeData.ownsVendor == true)
         {
            lines.push(this.modePieces());
         }
         this.showPanel(lines.length > 0 ? lines : null);
      }

      // Best deals in the open shop: its non-legendary items compared with the selling price of
      // at least DEAL_MIN_VENDORS other vendors, cheapest stack per item. Cached per list.
      private function dealsPieces(list:Array) : Array
      {
         var print:String = fingerprint(list) + "|" + this.historyVersion;
         var vendor:String = null;
         var cheapest:Object = {};
         var entry:Object = null;
         var key:String = null;
         var here:Number = NaN;
         var stats:Object = null;
         var deals:Array = [];
         var compared:int = 0;
         var line:Array = [piece("BEST DEALS","label")];
         var deal:Object = null;
         var known:Object = {};
         var knownCount:int = 0;
         if(print == this.dealsFor)
         {
            return this.dealsLine;
         }
         vendor = this.currentVendor();
         // Only a list accepted as this shop's (see processVendor), never a stale one.
         if(this.listOwners[fingerprint(list)] != vendor)
         {
            line.push(piece("waiting for this shop's item list","dim"));
            return line;
         }
         for each(entry in list)
         {
            if(entry == null || entry.isLegendary == true)
            {
               continue;
            }
            here = this.priceOf(entry,MODE_VENDING_MACHINE);
            if(isNaN(here))
            {
               continue;
            }
            key = itemKey(entry);
            // Plans and recipes you already know (the game flags them per viewer).
            if(entry.isLearnedRecipe == true)
            {
               known[key] = true;
               continue;
            }
            if(cheapest[key] == null || here < cheapest[key].here)
            {
               cheapest[key] = {"entry":entry,"here":here};
            }
         }
         for(key in cheapest)
         {
            stats = this.suggest(this.history[key] as Array,vendor);
            // Measured against the lower quartile whatever the selling method, so an
            // undercut seller still sees the same deals.
            if(int(stats.count) < DEAL_MIN_VENDORS || Number(stats.market) <= 0)
            {
               continue;
            }
            compared++;
            here = cheapest[key].here;
            if((here - stats.market) / stats.market * 100 <= -DEAL_MIN_PERCENT)
            {
               deals.push({
                  "name":shortName(String(cheapest[key].entry.text),DEAL_NAME_LENGTH),
                  "here":here,
                  "market":stats.market,
                  "ratio":here / stats.market
               });
            }
         }
         deals.sortOn("ratio",Array.NUMERIC);
         for(key in known)
         {
            knownCount++;
         }
         if(compared == 0)
         {
            line.push(piece("nothing here seen at " + DEAL_MIN_VENDORS + "+ other vendors yet","dim"));
         }
         else if(deals.length == 0)
         {
            line.push(piece("none " + DEAL_MIN_PERCENT + "%+ below market  (" + compared + " compared)","dim"));
         }
         else
         {
            line.push(piece(deals.length + " of " + compared + " compared","dim"));
            for each(deal in deals.slice(0,DEALS_SHOWN))
            {
               line.push(piece(deal.name,"gap"));
               line.push(piece(String(deal.here),"value"));
               line.push(percentPiece(deal.here,deal.market,true));
            }
         }
         if(knownCount > 0)
         {
            line.push(piece(knownCount + " known plans hidden","dimgap"));
         }
         this.dealsFor = print;
         this.dealsLine = line;
         this.diag.deals = linesText([line]);
         return line;
      }

      // The highlighted item: name, market price, vendors and range, and either this
      // shop's price or where your Better Containers price comes from. Null when the item
      // cannot be identified.
      private function highlightedPieces() : Array
      {
         var entry:Object = null;
         var key:String = null;
         var browsingOther:Boolean = false;
         var stats:Object = null;
         var here:Number = NaN;
         var legendary:Boolean = false;
         var exact:Boolean = false;
         var line:Array = [piece("PRICESCOUT","label")];
         entry = this.findEntry(this.cardHandle,this.cardText);
         if(entry == null)
         {
            // The lists may be stale; fetch them again and retry once.
            this.rewatch(OFFERS_PROVIDER,"highlighted item not in lists");
            this.rewatch(INVENTORY_PROVIDER,"highlighted item not in lists");
            entry = this.findEntry(this.cardHandle,this.cardText);
         }
         browsingOther = this.typeData.ownsVendor != true;
         exact = entry != null && Number(entry.serverHandleID) == this.cardHandle;
         if(entry != null && entry.isLegendary == true)
         {
            // Vendor lists show a legendary item's name (base item and 1st-star effect),
            // stars and level, never its other effects, so this is the closest match:
            // same name and stars, any level.
            legendary = true;
            key = itemKey(entry);
            stats = this.suggest(this.legendaryEntries(String(entry.text),int(entry.numLegendaryStars)),browsingOther ? this.currentVendor() : null,this.panelItemValue(entry,key));
            if(exact)
            {
               this.captureLegendaryCard(entry);
            }
         }
         else if(entry != null)
         {
            key = itemKey(entry);
            stats = this.suggest(this.history[key] as Array,browsingOther ? this.currentVendor() : null,this.panelItemValue(entry,key));
         }
         else if(this.cardText != null)
         {
            // Not in any list: match history by name, across levels and star counts.
            key = "name:" + plainName(this.cardText);
            stats = this.suggest(this.entriesByName(this.cardText),browsingOther ? this.currentVendor() : null);
         }
         else
         {
            this.diag.selection = "serverHandleID " + this.cardHandle + " not in any list, and no name";
            return null;
         }
         // Named, because Better Containers' Vendor manager has its own highlight that the
         // game never sees, so this line follows the window underneath instead.
         line.push(piece(shortName(entry != null ? String(entry.text) : this.cardText,ITEM_NAME_LENGTH),"name"));
         if(int(stats.count) == 0)
         {
            line.push(piece(browsingOther ? "no other vendors seen with this item yet" : "no prices seen yet","dimgap"));
         }
         else if(int(stats.count) < MARKET_MIN_VENDORS)
         {
            // One vendor's asking price is not a market: shown, but dimmed and unused.
            line.push(piece("1 vendor only","dimgap"));
            line.push(piece(String(stats.low),"dim"));
         }
         else
         {
            // Sell: by sellMethod, the lower quartile of vendors' prices by default,
            // competitive without matching the cheapest. Typical: the median asking price.
            line.push(piece("sell","dimgap"));
            line.push(piece(String(stats.sell),"price"));
            if(this.methodIsCustom() || stats.blended == true)
            {
               line.push(piece((this.methodIsCustom() ? this.methodText() : "") + (this.methodIsCustom() && stats.blended == true ? ", " : "") + (stats.blended == true ? "with item value" : ""),"dim"));
            }
            line.push(piece("typical " + stats.median,"dim"));
            line.push(piece(stats.count + " vendors   " + stats.low + "-" + stats.high,"dimgap"));
            if(legendary)
            {
               line.push(piece("same name & stars, other effects not compared","dim"));
            }
         }
         // Only an exact serverHandleID match is this vendor's listing.
         if(browsingOther && exact && int(stats.count) >= MARKET_MIN_VENDORS)
         {
            here = this.priceOf(entry,MODE_VENDING_MACHINE);
            if(!isNaN(here) && stats.sell > 0)
            {
               line.push(piece("here","dimgap"));
               line.push(piece(String(here),"value"));
               line.push(percentPiece(here,stats.sell,true));
            }
         }
         // At your own machine: where the price Better Containers will use comes from.
         if(!browsingOther && exact)
         {
            line = line.concat(this.ownPricePieces(entry,key,stats));
         }
         this.diag.selection = key + " -> " + linesText([line]);
         return line;
      }

      // For an item at your own machine: its listed price, or the price Better Containers
      // remembers for it and whether PriceScout or you set it.
      private function ownPricePieces(entry:Object, key:String, stats:Object) : Array
      {
         var listed:Number = this.priceOf(entry,MODE_VENDING_MACHINE);
         var saved:* = undefined;
         var hasMarket:Boolean = stats != null && int(stats.count) >= MARKET_MIN_VENDORS && Number(stats.sell) > 0;
         var out:Array = [];
         if(!isNaN(listed))
         {
            out.push(piece("listed at","dimgap"));
            out.push(piece(String(listed),"value"));
            if(hasMarket)
            {
               out.push(percentPiece(listed,stats.sell,false));
            }
            return out;
         }
         // Better Containers saves when you change a price, so re-read now and then.
         if(this.bcPrices == null || getTimer() - this.bcPricesAt > BC_REREAD_MS)
         {
            this.bcPricesAt = getTimer();
            this.loadBcPrices();
         }
         if(this.bcPrices == null)
         {
            return out;
         }
         saved = this.bcPrices[key];
         if(saved === undefined || saved === null)
         {
            out.push(piece("BC price: item value","dimgap"));
            return out;
         }
         if(this.feedWritten[key] !== undefined && Number(saved) == Number(this.feedWritten[key]))
         {
            out.push(piece("BC price","dimgap"));
            out.push(piece(String(saved),"value"));
            out.push(piece(hasMarket ? "from PriceScout" : this.markupText() + ", no market data","dim"));
            return out;
         }
         out.push(piece("your BC price","dimgap"));
         out.push(piece(String(saved),"value"));
         if(hasMarket)
         {
            out.push(percentPiece(Number(saved),stats.sell,false));
         }
         return out;
      }

      // At your own machine: market-price mode and its F10 switch.
      private function modePieces() : Array
      {
         var line:Array = [piece("MARKET MODE","label")];
         if(this.marketMode)
         {
            line.push(piece(this.visitApplied ? "ON" : "applying...","good"));
            line.push(piece("every BC price = market, " + this.markupText() + " when no data","dimgap"));
            line.push(piece("F10 to turn off","dimgap"));
         }
         else
         {
            line.push(piece("OFF","dim"));
            line.push(piece(this.visitApplied ? "your prices are back" : "F10 sets every BC price to market (" + this.markupText() + " when no data)","dimgap"));
         }
         if(this.appliedAfterManager)
         {
            line.push(piece("reopen this machine to load it into the Vendor manager","badgap"));
         }
         return line;
      }

      private function formatFor(style:String) : TextFormat
      {
         switch(style)
         {
            case "label":
               return new TextFormat(STATUS_FONT,13,COLOR_ACCENT,true);
            case "name":
               return new TextFormat(STATUS_FONT,16,COLOR_TEXT,true);
            case "price":
               return new TextFormat(STATUS_FONT,19,COLOR_ACCENT,true);
            case "value":
               return new TextFormat(STATUS_FONT,16,COLOR_TEXT,true);
            case "good":
               return new TextFormat(STATUS_FONT,15,COLOR_GOOD,true);
            case "bad":
            case "badgap":
               return new TextFormat(STATUS_FONT,15,COLOR_BAD,true);
            case "gap":
               return new TextFormat(STATUS_FONT,15,COLOR_TEXT,true);
            default:
               return new TextFormat(STATUS_FONT,14,COLOR_DIM,true);
         }
      }

      // Space before a piece: wider before a new group ("gap" styles), small otherwise.
      private static function spaceBefore(style:String) : Number
      {
         return style == "gap" || style == "dimgap" || style == "badgap" || style == "name" ? 22 : 8;
      }

      // lines: Array of piece arrays, or null to hide the panel.
      private function showPanel(lines:Array) : void
      {
         var used:int = 0;
         var line:Array = null;
         var p:Object = null;
         var field:TextField = null;
         var rows:Array = [];
         var pieces:Array = null;
         var row:Object = null;
         var cx:Number = 0;
         var lineHeight:Number = 0;
         var panelWidth:Number = 0;
         var panelHeight:Number = 0;
         var left:Number = NaN;
         var top:Number = NaN;
         var cy:Number = 0;
         var i:int = 0;
         if(lines == null)
         {
            for each(field in this.panelFields)
            {
               field.visible = false;
            }
            this.panelBox.visible = false;
            return;
         }
         try
         {
            // Measure: each piece's field placed at cx within its row.
            for each(line in lines)
            {
               pieces = [];
               cx = 0;
               lineHeight = 0;
               i = 0;
               for each(p in line)
               {
                  if(used >= this.panelFields.length)
                  {
                     field = this.makeText();
                     addChild(field);
                     this.panelFields.push(field);
                  }
                  field = this.panelFields[used++];
                  field.text = String(p.t);
                  field.setTextFormat(this.formatFor(String(p.s)));
                  if(i > 0)
                  {
                     cx += spaceBefore(String(p.s));
                  }
                  pieces.push({"field":field,"offset":cx});
                  cx += field.textWidth + 4;
                  lineHeight = Math.max(lineHeight,field.textHeight + 4);
                  i++;
               }
               rows.push({"pieces":pieces,"lineHeight":lineHeight});
               panelWidth = Math.max(panelWidth,cx);
               panelHeight += lineHeight + (rows.length > 1 ? PANEL_LINE_GAP : 0);
            }
            for(i = used; i < this.panelFields.length; i++)
            {
               this.panelFields[i].visible = false;
            }
            left = PANEL_CENTER_X - (panelWidth + PANEL_PAD_X * 2) / 2;
            top = PANEL_BOTTOM - (panelHeight + PANEL_PAD_Y * 2);
            this.panelBox.graphics.clear();
            this.panelBox.graphics.beginFill(COLOR_PANEL,PANEL_ALPHA);
            this.panelBox.graphics.drawRect(left,top,panelWidth + PANEL_PAD_X * 2,panelHeight + PANEL_PAD_Y * 2);
            this.panelBox.graphics.endFill();
            this.panelBox.graphics.beginFill(COLOR_ACCENT,0.6);
            this.panelBox.graphics.drawRect(left,top,panelWidth + PANEL_PAD_X * 2,2);
            this.panelBox.graphics.endFill();
            this.panelBox.visible = true;
            // Place: pieces share a bottom edge within their row.
            cy = top + PANEL_PAD_Y;
            for each(row in rows)
            {
               for each(p in row.pieces)
               {
                  field = p.field;
                  field.x = left + PANEL_PAD_X + p.offset;
                  field.y = cy + row.lineHeight - (field.textHeight + 4);
                  field.visible = true;
               }
               cy += row.lineHeight + PANEL_LINE_GAP;
            }
         }
         catch(error:Error)
         {
            this.addError("price panel: " + error.message);
         }
      }

      // ---- On-screen status ---------------------------------------------------------

      // Same setup Better Containers uses for its runtime text: the game's font library
      // name, embedded fonts, and the format applied again after every text change.
      // The backing box is plain vector art, so it shows even if the font does not.
      private function createStatus() : void
      {
         this.statusFormat = new TextFormat(STATUS_FONT,16,0xFFFFFF,true);
         this.statusBox = new Shape();
         this.statusBox.x = STATUS_X;
         this.statusBox.y = STATUS_Y;
         addChild(this.statusBox);
         this.status = this.makeText();
         this.status.x = STATUS_X + STATUS_PAD;
         this.status.y = STATUS_Y + STATUS_PAD;
         this.status.visible = false;
         this.statusBox.visible = false;
         addChild(this.status);
         this.panelBox = new Shape();
         this.panelBox.visible = false;
         addChild(this.panelBox);
      }

      private function makeText() : TextField
      {
         var field:TextField = new TextField();
         field.embedFonts = true;
         field.antiAliasType = AntiAliasType.ADVANCED;
         field.selectable = false;
         field.mouseEnabled = false;
         field.multiline = false;
         field.wordWrap = false;
         field.autoSize = TextFieldAutoSize.LEFT;
         field.defaultTextFormat = this.statusFormat;
         field.filters = [new GlowFilter(0,1,3,3,2)];
         return field;
      }

      // The status line only shows during normal play, and only when xScal storage could
      // not be reached (nothing would be saved). In shops the price panel shows instead.
      private function applyStatusVisibility() : void
      {
         var show:Boolean = !this.menuOpen() && this.codeObj == null && String(this.diag.codeObject).indexOf("timeout") == 0;
         if(this.status != null)
         {
            this.status.visible = show;
            this.statusBox.visible = show;
         }
      }

      private function onHudMode(mode:String) : void
      {
         var show:Boolean = mode == null || STATUS_HUD_MODES.indexOf(mode) >= 0;
         this.hudMode = mode;
         if(this.diag.hudMode != mode)
         {
            this.diag.hudMode = mode;
            this.logEvent("hudMode " + mode);
            if(show)
            {
               this.onMenuClosed();
            }
         }
         this.applyStatusVisibility();
         this.refreshPanel();
      }

      private function updateStatus() : void
      {
         var storage:String = this.codeObj != null ? "storage ok" : String(this.diag.codeObject);
         this.setStatus(storage + " | vendor events " + (int(this.diag.events[INVENTORY_PROVIDER]) + int(this.diag.events[OFFERS_PROVIDER])) + " | prices " + int(this.diag.recorded));
         this.applyStatusVisibility();
      }

      private function setStatus(text:String) : void
      {
         var boxWidth:Number = NaN;
         var boxHeight:Number = NaN;
         if(this.status == null)
         {
            return;
         }
         try
         {
            this.status.text = "PriceScout " + BUILD + ": " + text;
            this.status.setTextFormat(this.statusFormat);
            boxWidth = this.status.textWidth > 0 ? this.status.textWidth + 4 : 360;
            boxHeight = this.status.textHeight > 0 ? this.status.textHeight + 4 : 22;
            this.statusBox.graphics.clear();
            this.statusBox.graphics.beginFill(0,0.55);
            this.statusBox.graphics.drawRect(0,0,boxWidth + STATUS_PAD * 2,boxHeight + STATUS_PAD * 2);
            this.statusBox.graphics.endFill();
            this.diag.statusText = {
               "font":STATUS_FONT,
               "textWidth":this.status.textWidth,
               "textHeight":this.status.textHeight,
               "visible":this.visible && this.status.visible,
               "onStage":this.status.stage != null,
               "alpha":this.alpha
            };
         }
         catch(error:Error)
         {
            this.addError("status text: " + error.message);
         }
      }

      private function addError(text:String) : void
      {
         var errors:Array = this.diag.errors as Array;
         this.diagMustSave = true;
         errors.push(text);
         if(errors.length > MAX_ERRORS)
         {
            errors.shift();
         }
         this.diagDirty = true;
      }

      private function reportFatal(text:String) : void
      {
         this.addError(text);
         this.setStatus(text);
         try
         {
            this.topLevel.displayError("PriceScout: " + text);
         }
         catch(error:Error)
         {
         }
      }

      // ---- Helpers ------------------------------------------------------------------

      private static function nowSeconds() : Number
      {
         return Math.floor(new Date().time / 1000);
      }

      private static function hashText(text:String) : String
      {
         var h:uint = 5381;
         var i:int = 0;
         while(i < text.length)
         {
            h = uint(h * 33) ^ uint(text.charCodeAt(i));
            i++;
         }
         return h.toString(16);
      }

      // Copy of a game data object that is safe to serialize: primitives, nested to depth.
      private static function dump(value:*, depth:int) : *
      {
         var out:Object = null;
         var key:String = null;
         var text:String = null;
         if(value === null || value === undefined)
         {
            return null;
         }
         if(value is Boolean || value is Number)
         {
            return value;
         }
         if(value is String)
         {
            text = String(value);
            return text.length > 120 ? text.substr(0,120) + "..." : text;
         }
         if(value is Array)
         {
            if(depth <= 0)
            {
               return "[array " + (value as Array).length + "]";
            }
            return {
               "arrayLength":(value as Array).length,
               "first":((value as Array).length > 0 ? dump(value[0],depth - 1) : null)
            };
         }
         if(value is Function)
         {
            return "[function]";
         }
         out = {};
         for(key in value)
         {
            out[key] = depth > 0 ? dump(value[key],depth - 1) : typeName(value[key]);
         }
         return out;
      }

      private static function typeName(value:*) : String
      {
         if(value === null || value === undefined)
         {
            return "null";
         }
         if(value is Array)
         {
            return "array";
         }
         return typeof value;
      }

      private static function encode(value:*) : String
      {
         var parts:Array = null;
         var key:String = null;
         var item:* = undefined;
         if(value === null || value === undefined || value is Function)
         {
            return "null";
         }
         if(value is String)
         {
            return quote(String(value));
         }
         if(value is Boolean)
         {
            return value ? "true" : "false";
         }
         if(value is Number)
         {
            return isFinite(value) ? String(value) : "null";
         }
         parts = [];
         if(value is Array)
         {
            for each(item in value)
            {
               parts.push(encode(item));
            }
            return "[" + parts.join(",") + "]";
         }
         for(key in value)
         {
            parts.push(quote(key) + ":" + encode(value[key]));
         }
         return "{" + parts.join(",") + "}";
      }

      private static function quote(text:String) : String
      {
         var out:String = "\"";
         var i:int = 0;
         var code:int = 0;
         var hex:String = null;
         // Most strings need no escaping: return them without the per-character loop.
         if(text.search(NEEDS_ESCAPE) < 0)
         {
            return "\"" + text + "\"";
         }
         while(i < text.length)
         {
            code = text.charCodeAt(i);
            if(code == 34)
            {
               out += "\\\"";
            }
            else if(code == 92)
            {
               out += "\\\\";
            }
            else if(code < 32)
            {
               hex = code.toString(16);
               while(hex.length < 4)
               {
                  hex = "0" + hex;
               }
               out += "\\u" + hex;
            }
            else
            {
               out += text.charAt(i);
            }
            i++;
         }
         return out + "\"";
      }

      // Small JSON reader; Scaleform has no native JSON class.
      private function parseJson(text:String) : *
      {
         var value:* = undefined;
         this.jsonText = text;
         this.jsonPos = 0;
         this.jsonBackslash = -1;
         value = this.jsonValue();
         this.jsonSpace();
         if(this.jsonPos != this.jsonText.length)
         {
            throw new Error("JSON: trailing text at " + this.jsonPos);
         }
         return value;
      }

      private function jsonSpace() : void
      {
         var c:String = null;
         while(this.jsonPos < this.jsonText.length)
         {
            c = this.jsonText.charAt(this.jsonPos);
            if(c != " " && c != "\t" && c != "\n" && c != "\r")
            {
               return;
            }
            this.jsonPos++;
         }
      }

      private function jsonValue() : *
      {
         var c:String = null;
         this.jsonSpace();
         c = this.jsonText.charAt(this.jsonPos);
         if(c == "{")
         {
            return this.jsonObject();
         }
         if(c == "[")
         {
            return this.jsonArray();
         }
         if(c == "\"")
         {
            return this.jsonString();
         }
         if(this.jsonText.substr(this.jsonPos,4) == "true")
         {
            this.jsonPos += 4;
            return true;
         }
         if(this.jsonText.substr(this.jsonPos,5) == "false")
         {
            this.jsonPos += 5;
            return false;
         }
         if(this.jsonText.substr(this.jsonPos,4) == "null")
         {
            this.jsonPos += 4;
            return null;
         }
         return this.jsonNumber();
      }

      private function jsonObject() : Object
      {
         var out:Object = {};
         var key:String = null;
         this.jsonPos++;
         this.jsonSpace();
         if(this.jsonText.charAt(this.jsonPos) == "}")
         {
            this.jsonPos++;
            return out;
         }
         while(true)
         {
            this.jsonSpace();
            key = this.jsonString();
            this.jsonSpace();
            if(this.jsonText.charAt(this.jsonPos) != ":")
            {
               throw new Error("JSON: expected : at " + this.jsonPos);
            }
            this.jsonPos++;
            out[key] = this.jsonValue();
            this.jsonSpace();
            if(this.jsonText.charAt(this.jsonPos) == ",")
            {
               this.jsonPos++;
               continue;
            }
            if(this.jsonText.charAt(this.jsonPos) == "}")
            {
               this.jsonPos++;
               return out;
            }
            throw new Error("JSON: expected , or } at " + this.jsonPos);
         }
         return out;
      }

      private function jsonArray() : Array
      {
         var out:Array = [];
         this.jsonPos++;
         this.jsonSpace();
         if(this.jsonText.charAt(this.jsonPos) == "]")
         {
            this.jsonPos++;
            return out;
         }
         while(true)
         {
            out.push(this.jsonValue());
            this.jsonSpace();
            if(this.jsonText.charAt(this.jsonPos) == ",")
            {
               this.jsonPos++;
               continue;
            }
            if(this.jsonText.charAt(this.jsonPos) == "]")
            {
               this.jsonPos++;
               return out;
            }
            throw new Error("JSON: expected , or ] at " + this.jsonPos);
         }
         return out;
      }

      // Copies each run of plain characters in one substring, stopping only at the closing
      // quote or a backslash; building strings a character at a time is slow in Scaleform.
      private function jsonString() : String
      {
         var out:String = "";
         var c:String = null;
         var close:int = 0;
         if(this.jsonText.charAt(this.jsonPos) != "\"")
         {
            throw new Error("JSON: expected string at " + this.jsonPos);
         }
         this.jsonPos++;
         while(true)
         {
            close = this.jsonText.indexOf("\"",this.jsonPos);
            if(close < 0)
            {
               throw new Error("JSON: unterminated string");
            }
            // The next backslash is found once and reused until passed, so plain text is
            // not rescanned for each string.
            if(this.jsonBackslash < this.jsonPos)
            {
               this.jsonBackslash = this.jsonText.indexOf("\\",this.jsonPos);
               if(this.jsonBackslash < 0)
               {
                  this.jsonBackslash = this.jsonText.length;
               }
            }
            if(this.jsonBackslash > close)
            {
               out += this.jsonText.substring(this.jsonPos,close);
               this.jsonPos = close + 1;
               return out;
            }
            out += this.jsonText.substring(this.jsonPos,this.jsonBackslash);
            this.jsonPos = this.jsonBackslash + 1;
            c = this.jsonText.charAt(this.jsonPos++);
            if(c == "u")
            {
               out += String.fromCharCode(parseInt(this.jsonText.substr(this.jsonPos,4),16));
               this.jsonPos += 4;
            }
            else if(c == "n")
            {
               out += "\n";
            }
            else if(c == "r")
            {
               out += "\r";
            }
            else if(c == "t")
            {
               out += "\t";
            }
            else if(c == "b")
            {
               out += "\b";
            }
            else if(c == "f")
            {
               out += "\f";
            }
            else
            {
               out += c;
            }
         }
         throw new Error("JSON: unterminated string");
      }

      private function jsonNumber() : Number
      {
         var start:int = this.jsonPos;
         var value:Number = NaN;
         while(this.jsonPos < this.jsonText.length && "+-0123456789.eE".indexOf(this.jsonText.charAt(this.jsonPos)) >= 0)
         {
            this.jsonPos++;
         }
         value = Number(this.jsonText.substring(start,this.jsonPos));
         if(start == this.jsonPos || isNaN(value))
         {
            throw new Error("JSON: bad value at " + start);
         }
         return value;
      }
   }
}
