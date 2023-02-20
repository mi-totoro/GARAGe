import mysql.connector
import os
import re
import datetime as dt
import requests
import errno
import shutil
import json
import random
import sys
import argparse
import Table
from pprint import pprint
import re
import AODDB
import Atlas
from googleapiclient.discovery import build
from google_auth_oauthlib.flow import InstalledAppFlow
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
import subprocess


path = os.path.dirname(os.path.realpath(__file__))



class Mutation(Table.Table):
    def __init__(self, mutationId):
        self.TableName = 'Mutation'
        self.primary = 'mutationId'
        self.info = {}
        self.config = Table.read_config()
        self.getFieldDic()
        if type(mutationId) == int:
            self.getFieldInfo(mutationId)
        elif mutationId.isdigit():
            self.getFieldInfo(mutationId)
        elif Atlas.parse_mutationName(mutationId):
            mut = Atlas.parse_mutationName(mutationId)
            mutationId = AODDB.select_single(f"SELECT mutationId FROM Mutation WHERE mutationChr = '{mut['chr']}' AND mutationGenomicPos = '{mut['pos']}' AND mutationRef = '{mut['ref']}' AND mutationAlt = '{mut['alt']}'")
            if mutationId:
                self.getFieldInfo(mutationId)
            else:
                self.info = None
        else:
            self.info = None

    def mutationName(self):
        name = self.info['mutationChr'].lower() + ':' + str(self.info['mutationGenomicPos']) + self.info['mutationRef'].upper() + '>' + self.info['mutationAlt'].upper()
        return name

class MutationRule(Table.Table):
    def __init__(self, inputId):
        self.TableName = 'MutationRule'
        self.primary = 'mutationRuleId'
        self.info = {}
        self.config = Table.read_config()
        self.getFieldDic()
        if type(inputId) == int:
            self.getFieldInfo(inputId)
        elif inputId.isdigit():
            self.getFieldInfo(inputId)
        elif Atlas.parse_mutationRule(inputId):
            mut = Atlas.parse_mutationRule(inputId)
            inputId = AODDB.select_single(f"select mutationruleid from MutationRule INNER JOIN Mutation ON Mutation.mutationId = MutationRule.mutationId where Mutation.mutationChr = '{mut['chr']}' and Mutation.mutationGenomicPos = '{mut['pos']}' and Mutation.mutationRef = '{mut['ref']}' and Mutation.mutationAlt = '{mut['alt']}' and MutationRule.zygosity = '{mut['zygosity']}';");
            if inputId:
                self.getFieldInfo(inputId)
            else:
                self.info = None
        else:
            self.info = None

    def Mutation(self):
        return Mutation(self.info['mutationId'])

    def name(self):
        mut = self.Mutation()
        return (mut.mutationName() + ':' + self.info['zygosity'])
    

class MolecularTarget(Table.Table):
    def __init__(self, inputId):
        self.TableName = 'MolecularTarget'
        self.primary = 'molecularTargetId'
        self.info = {}
        self.config = Table.read_config()
        self.getFieldDic()
        inputId = int(subprocess.check_output(f"perl {path}/MolecularTarget.pl '{inputId}'", shell=True))
        self.getFieldInfo(inputId)
        
class VariantInterpretation(Table.Table):
    def __init__(self, inputId):
        self.TableName = 'VariantInterpretation'
        self.primary = 'variantInterpretationId'
        self.info = {}
        self.config = Table.read_config()
        self.getFieldDic()
        if type(inputId) == int:
            self.getFieldInfo(inputId)
        elif inputId.isdigit():
            self.getFieldInfo(inputId)
        elif Atlas.parse_variantInterpretation(inputId):
            mut = Atlas.parse_variantInterpretation(inputId)
            inputId = AODDB.select_single(f"select variantinterpretationid from `VariantInterpretation` where molecularTargetId = '{mut['MT']}' and phenotypeId = '{mut['PH']}';");
            if inputId:
                self.getFieldInfo(inputId)
            else:
                self.info = None
        else:
            self.info = None

class Player(Table.Table):
    def __init__(self, inputId):
        self.TableName = 'Player'
        self.primary = 'playerName'
        self.info = {}
        self.config = Table.read_config()
        self.getFieldDic()
        self.getFieldInfo(str(inputId))













