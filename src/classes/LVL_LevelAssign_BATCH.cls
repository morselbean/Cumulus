/*
    Copyright (c) 2016, Salesforce.org
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are met:
    
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright
      notice, this list of conditions and the following disclaimer in the
      documentation and/or other materials provided with the distribution.
    * Neither the name of Salesforce.org nor the names of
      its contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.
 
    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT 
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS 
    FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE 
    COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, 
    INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, 
    BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; 
    LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER 
    CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT 
    LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN 
    ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE 
    POSSIBILITY OF SUCH DAMAGE.
*/
/**
* @author Salesforce.org
* @date 2016
* @group Level
* @group-content ../../ApexDocContent/Levels.htm
* @description Batch class processes all Levels against Target objects, and updates any changes.
*/
public without sharing class LVL_LevelAssign_BATCH implements Database.Batchable<sObject>, Database.Stateful {
    
    /** @description The query for the batch process to run on.*/
    private String strSoql;

    /** @description The Object name that we are running the batch process on.*/
    private String strObject;
    
    /** @description The Ladder Levels to run on this object */
    private map<String, list<Level__c>> mapLadderToLevels;
    
    /*********************************************************************************************************
    * @description The batch process constructor; creates opportunity query for all opportunities.
    */
    public LVL_LevelAssign_BATCH(String strSoql, String strObject) {
        this.strSoql = strSoql;
        this.strObject = strObject;

        // get our map of Ladder Levels
        this.mapLadderToLevels = mapLadderToLevelsForObject(strObject);
    }
    
    /*********************************************************************************************************
    * @description Batch process start method.
    */
    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator(strSoql);
    }

    /*********************************************************************************************************
    * @description Batch process execute method. Goes thru each object, and evaluates it against each 
    * ladder, and only updates it if levels change.
    */
    public void execute(Database.BatchableContext BC, List<sObject> scope) {
        
        // track our objects to update
        map<Id, SObject> mapSObjUpdate = new map<Id, SObject>();
        
        // for each of our objects
        for (SObject sobj : scope) {
            
            // for each of our Ladders
            for (String strLadder : mapLadderToLevels.keySet()) {
                list<Level__c> listLvls = mapLadderToLevels.get(strLadder);
                
                // go thru each list of Levels finding where this object fits
                for (Level__c lvl : listLvls) {
                    Decimal amt = (Decimal)sobj.get(lvl.Source_Field__c);
                    if (amt != null) {
                        if (amt >= lvl.Minimum_Amount__c && amt <= lvl.Maximum_Amount__c) {
                            
                            // record the new level
                            Id lvlIdPrev = (Id)sobj.get(strLadder);
                            if (lvlIdPrev != lvl.Id) {
                                if (lvl.Previous_Level_Field__c != null)
                                    sobj.put(lvl.Previous_Level_Field__c, lvlIdPrev);
                                sobj.put(strLadder, lvl.Id);
                                mapSObjUpdate.put(sobj.Id, sobj);
                            }
                            // done with this level.
                            break;
                        }
                    }
                } // levels               
            } // ladder            
        } // scope
                
        // save 'em
        update mapSObjUpdate.values();     
    }
    
    /*********************************************************************************************************
    * @description Batch process finish method, does nothing.
    */
    public void finish(Database.BatchableContext BC) {}
    
    /*********************************************************************************************************
    * @description For the given object, return a map from it's different Ladders (Level_Field__c), to the
    * appropriate Levels for that Ladder. The levels are stored in increasing order for Minimum Amount.
    * @param strObj The object to get the ladder levels for
    * @return map<String, list<Level__c>> The map of Ladder Levels for the object
    */
    public static map<String, list<Level__c>> mapLadderToLevelsForObject(String strObj) {
        
        // get all our levels for this object type
        list<Level__c> listAllLvls = [select Id, Name, Target__c, Source_Field__c, Level_Field__c, 
            Previous_Level_Field__c, Active__c, Minimum_Amount__c, Maximum_Amount__c, Engagement_Plan__c
            from Level__c
            where Target__c = :strObj and Active__c = true
            order by Level_Field__c asc, Minimum_Amount__c asc];
            
        // create our map to store the list of Levels per Ladder
        map<String, list<Level__c>> mapLadderToLvls = new map<String, list<Level__c>>();
        
        for (Level__c lvl : listAllLvls) {
            string ladder = lvl.Level_Field__c;
            list<Level__c> listLvls = mapLadderToLvls.get(ladder);
            if (listLvls == null) {
                listLvls = new list<Level__c>();
                mapLadderToLvls.put(ladder, listLvls);
            }
            listLvls.add(lvl);
        }
        
        // we now have a map from Ladder to its list of Levels
        return mapLadderToLvls;         
    }
    
    /*********************************************************************************************************
    * @description query the Level object, and return a map of Object Name to a Set of Fields to query.
    * @return map<String, list<String>> The map of Object Name to its Set of Fields
    */
    public static map<String, set<String>> getMapStrObjectToQueryFields() {
        
        // get all our levels
        list<Level__c> listAllLvls = [select Id, Name, Target__c, Source_Field__c, Level_Field__c, 
            Previous_Level_Field__c, Active__c
            from Level__c
            where Active__c = true
            order by Target__c, Level_Field__c];
            
        // create our map
        map<String, set<String>> mapStrObjectToQueryFields = new map<String, set<String>>();
        
        for (Level__c lvl : listAllLvls) {
            // for each object, we'll add all its source, level, and previous level fields
            String strObj = lvl.Target__c;
            Set<String> setFlds = mapStrObjectToQueryFields.get(strObj);
            if (setFlds == null) {
                setFlds = new Set<String>();
                mapStrObjectToQueryFields.put(strObj, setFlds);
            }
            setFlds.add(lvl.Source_Field__c);
            setFlds.add(lvl.Level_Field__c);
            if (lvl.Previous_Level_Field__c != null)
                setFlds.add(lvl.Previous_Level_Field__c);            
        }
        
        return mapStrObjectToQueryFields; 
    }
}